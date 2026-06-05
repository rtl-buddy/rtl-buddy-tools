#!/bin/bash
# install-prereqs-linux.sh — user-space installs of the deps that brew provides
# on macOS (README "brew install" line) but Rocky 8 lacks, into $PREFIX.
# Covers: gperf (build dep), z3, iverilog, lcov, yices2.
# Not handled: verible (module load verible), gtkwave/graphviz (system),
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

# --- z3 (sby solver) ---
if ! command -v z3 >/dev/null; then
  log z3
  cd "$SRC"
  [ -d z3 ] || git clone --depth 1 -b z3-4.13.4 https://github.com/Z3Prover/z3
  cmake -S z3 -B z3/build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" -DZ3_BUILD_LIBZ3_SHARED=OFF >/dev/null \
    && cmake --build z3/build -j"$JOBS" >/dev/null \
    && cmake --install z3/build >/dev/null || { echo "z3 FAILED"; fail=1; }
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

# --- yices2 (second sby solver) ---
if ! command -v yices >/dev/null; then
  log yices2
  cd "$SRC"
  [ -d yices2 ] || git clone --depth 1 -b Yices-2.6.4 https://github.com/SRI-CSL/yices2
  cd yices2
  autoconf >/dev/null
  ./configure --prefix="$PREFIX" >/dev/null && make -j"$JOBS" >/dev/null && make install >/dev/null || { echo "yices2 FAILED"; fail=1; }
fi

log "done (fail=$fail)"
for t in gperf z3 iverilog lcov yices; do
  command -v "$t" >/dev/null && echo "$t: $("$t" --version 2>&1 | head -1)" || echo "$t: MISSING"
done
exit $fail
