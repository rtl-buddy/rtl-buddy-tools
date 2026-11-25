#!/bin/bash
# install-prereqs-linux.sh — user-space installs of the deps that brew provides
# on macOS (README "brew install" line) but Rocky 8 lacks, into $PREFIX.
# Covers: build deps (bison, flex, gperf, readline, Tcl, help2man), iverilog,
# lcov, yaml-cpp. The solvers are pinned by the Makefile, not here: yices and
# boolector are submodules, z3 is the z3-solver wheel in sby-venv.
# Not handled: gtkwave/graphviz (system),
# klayout (no root; install separately if rb pnr GDS export is needed).
set -uo pipefail
PREFIX="${PREFIX:-$HOME/.local}"
SRC="$PREFIX/src"
JOBS="${JOBS:-32}"
mkdir -p "$SRC" "$PREFIX/bin"
export PATH="$PREFIX/bin:$PATH"

log() { echo "=== [$(date +%H:%M:%S)] $*"; }

fail=0

# --- gmake alias: cmake prefers `gmake` (system 4.2.1, no fifo-jobserver
# support) over the module make 4.4.1; alias it so sub-builds inherit the
# jobserver correctly ---
if [ ! -e "$PREFIX/bin/gmake" ]; then
  ln -s "$(command -v make)" "$PREFIX/bin/gmake"
fi

# --- help2man (verilator man pages; missing on Rocky 8) ---
if ! command -v help2man >/dev/null; then
  log help2man
  cd "$SRC"
  curl -fsSLO https://ftp.gnu.org/gnu/help2man/help2man-1.49.3.tar.xz
  tar xf help2man-1.49.3.tar.xz && cd help2man-1.49.3
  ./configure --prefix="$PREFIX" >/dev/null && make >/dev/null && make install >/dev/null || { echo "help2man FAILED"; fail=1; }
fi

# --- bison >= 3.6 (yosys, verilator; Rocky 8 ships 3.0.4) ---
if ! bison --version 2>/dev/null | grep -qE ' 3\.[6-9]| 3\.[1-9][0-9]'; then
  log bison
  cd "$SRC"
  curl -fsSLO https://ftp.gnu.org/gnu/bison/bison-3.8.2.tar.gz
  tar xf bison-3.8.2.tar.gz && cd bison-3.8.2
  ./configure --prefix="$PREFIX" >/dev/null && make -j"$JOBS" >/dev/null && make install >/dev/null || { echo "bison FAILED"; fail=1; }
fi

# --- gperf (needed to build iverilog & yices from git) ---
if ! command -v gperf >/dev/null; then
  log gperf
  cd "$SRC"
  curl -fsSLO https://ftp.gnu.org/gnu/gperf/gperf-3.1.tar.gz
  tar xf gperf-3.1.tar.gz && cd gperf-3.1
  ./configure --prefix="$PREFIX" >/dev/null && make -j"$JOBS" >/dev/null && make install >/dev/null || { echo "gperf FAILED"; fail=1; }
fi

# --- iverilog ---
if ! command -v iverilog >/dev/null; then
  log iverilog
  cd "$SRC"
  [ -d iverilog ] || git clone --depth 1 -b v12_0 https://github.com/steveicarus/iverilog
  cd iverilog
  sh autoconf.sh >/dev/null 2>&1
  ./configure --prefix="$PREFIX" >/dev/null && make -j"$JOBS" >/dev/null && make install >/dev/null || { echo "iverilog FAILED"; fail=1; }
fi

# --- lcov (1.16: no extra perl-module deps, matches verilator coverage flow) ---
if ! command -v lcov >/dev/null; then
  log lcov
  cd "$SRC"
  curl -fsSL https://github.com/linux-test-project/lcov/releases/download/v1.16/lcov-1.16.tar.gz | tar xz
  cd lcov-1.16 && make install PREFIX="$PREFIX" >/dev/null || { echo "lcov FAILED"; fail=1; }
fi

# --- yaml-cpp (OpenROAD 3dblox; not covered by its DependencyInstaller) ---
if [ ! -f "$PREFIX/lib64/libyaml-cpp.a" ] && [ ! -f "$PREFIX/lib/libyaml-cpp.a" ]; then
  log yaml-cpp
  cd "$SRC"
  [ -d yaml-cpp ] || git clone --depth 1 -b 0.8.0 https://github.com/jbeder/yaml-cpp
  cmake -S yaml-cpp -B yaml-cpp/build -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" -DYAML_BUILD_SHARED_LIBS=OFF \
    -DYAML_CPP_BUILD_TESTS=OFF >/dev/null \
    && cmake --build yaml-cpp/build -j"$JOBS" >/dev/null \
    && cmake --install yaml-cpp/build >/dev/null || { echo "yaml-cpp FAILED"; fail=1; }
fi

# --- flex (yosys; Rocky 8 has none without the devel repos) ---
if ! command -v flex >/dev/null; then
  log flex
  cd "$SRC"
  curl -fsSLO https://github.com/westes/flex/releases/download/v2.6.4/flex-2.6.4.tar.gz
  tar xf flex-2.6.4.tar.gz && cd flex-2.6.4
  ./configure --prefix="$PREFIX" >/dev/null && make -j"$JOBS" >/dev/null && make install >/dev/null || { echo "flex FAILED"; fail=1; }
fi

# --- readline (yosys shell; skipped when readline-devel is installed) ---
# Links the system libtinfo by full path: there is no libtinfo.so dev
# symlink or ncurses.pc without ncurses-devel. The compiler finds it in the
# host's own library dirs (/usr/lib64 on Rocky, the multiarch dir on Debian
# and Ubuntu).
# pkg-config with the same search dirs the Makefile gives yosys's CMake:
# $PREFIX first, then pkg-config's own system dirs (no PKG_CONFIG_PATH).
SYS_PC=$(pkg-config --variable pc_path pkg-config)
has_pc() { PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig:$SYS_PC" pkg-config --exists "$1"; }
if ! has_pc readline; then
  log readline
  TINFO=$(${CC:-gcc} -print-file-name=libtinfo.so.6)
  [[ $TINFO == /* ]] || { echo "readline: no libtinfo.so.6 found by ${CC:-gcc}"; exit 1; }
  cd "$SRC"
  curl -fsSLO https://ftp.gnu.org/gnu/readline/readline-8.2.tar.gz
  tar xf readline-8.2.tar.gz && cd readline-8.2
  ./configure --prefix="$PREFIX" --disable-static --with-curses >/dev/null \
    && make -j"$JOBS" SHLIB_LIBS="$TINFO" >/dev/null \
    && make install SHLIB_LIBS="$TINFO" >/dev/null \
    && sed -i '/^Requires.private:/d' "$PREFIX/lib/pkgconfig/readline.pc" || { echo "readline FAILED"; fail=1; }
fi

# --- Tcl 8.6 (yosys `-c` scripts and `tcl`; skipped when tcl-devel is installed) ---
if ! has_pc tcl; then
  log tcl
  cd "$SRC"
  curl -fsSL -o tcl8.6.16-src.tar.gz https://prdownloads.sourceforge.net/tcl/tcl8.6.16-src.tar.gz
  tar xf tcl8.6.16-src.tar.gz && cd tcl8.6.16/unix
  ./configure --prefix="$PREFIX" --enable-shared --enable-threads >/dev/null \
    && make -j"$JOBS" >/dev/null \
    && make install-binaries install-libraries install-headers >/dev/null || { echo "tcl FAILED"; fail=1; }
fi

log "done (fail=$fail)"
for t in bison flex gperf iverilog lcov; do
  command -v "$t" >/dev/null && echo "$t: $("$t" --version 2>&1 | head -1)" || echo "$t: MISSING"
done
exit $fail
