# rtl-buddy tools — macOS / Linux installer

One repo that clones, pins, and builds every external EDA tool
[rtl_buddy](https://github.com/rtl-buddy/rtl_buddy) depends on. Each tool is a
git submodule at a validated ref; the top-level `Makefile` encodes the exact
build recipe per OS (`uname -s` selects the branch); `bin/` ends up with a
symlink to every binary.

## Quick start (macOS)

```sh
git clone --recursive https://github.com/rtl-buddy/rtl-buddy-tools.git
cd rtl-buddy-tools

# prerequisites — Apple Silicon or Intel (brew prefix auto-detected);
# Xcode CLT assumed (xcode-select --install)
brew install bison flex cmake llvm boost eigen spdlog or-tools tcl-tk@8 swig \
             gtkwave graphviz lcov icarus-verilog gmp gperf autoconf \
             uv make bazelisk
# bazelisk is required by `make verible` (bazel source build; the Makefile
# pins the bazel version verible's own CI uses via USE_BAZEL_VERSION)
# brew `make` (GNU make 4.x) is required by `make verilator`: Apple's make
# 3.81 mishandles verilator's .SECONDARY intermediates and silently never
# links verilator_coverage_bin_dbg (install then fails with Error 71).
# uv (rtl_buddy's package manager) is also required by `make sby`: it builds
# sby's venv on uv's CPython 3.11 — the same interpreter rb runs on, instead of
# the ambient python3 (see SBY_PYTHON in the Makefile). Usually already present
# wherever rb is installed.
# gmp/gperf/autoconf: `make yices` (pinned source build, GMP linked statically).
# Do not also `brew install yices2`: the pinned build must win on PATH.
# z3 is not from brew either: `make sby` pins it (z3-solver wheel, bin/z3).
# Rust toolchain (surfer, veridian): https://rustup.rs
# OpenROAD's lemon/cudd deps (once):
#   cd OpenROAD && ./etc/DependencyInstaller.sh -prefix $HOME/.local && cd ..

make all          # everything (OpenROAD takes hours)
# or individually, e.g.:
make yosys yosys-slang yices boolector verilator surfer sby

source env-macos.zsh  # puts bin/ on PATH, unsets VERILATOR_ROOT,
                      # exports RTL_BUDDY_SLANG_PLUGIN
```

## Quick start (Linux — validated on Rocky 8.10, no root)

Assumes a toolchain with gcc >= 12 and cmake >= 3.28 on PATH (Yosys 0.71's minimum) (e.g. via
`module load gcc cmake`) plus system `zlib-devel libffi-devel`. Everything
else installs to `~/.local` / `~/.cargo` (readline and Tcl too, when
`readline-devel` / `tcl-devel` are absent; yices builds its own static GMP):

```sh
git clone --recursive https://github.com/rtl-buddy/rtl-buddy-tools.git
cd rtl-buddy-tools

# Rust toolchain (surfer, veridian):
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
# bison 3.8, flex, gperf, readline, Tcl, help2man, yaml-cpp, iverilog, lcov,
# gmake alias:
./install-prereqs-linux.sh
# OpenROAD's boost/eigen/lemon/cudd/or-tools/swig deps (once):
#   cd OpenROAD && ./etc/DependencyInstaller.sh -common -prefix=$HOME/.local && cd ..

cp site-env.sh.example site-env.sh   # machine-local env (gcc/ccache runtime, SystemC, node) — adjust paths
make all          # everything (OpenROAD is the long pole)
source env-linux.sh   # sources site-env.sh, then puts bin/ + ~/.local/bin + ~/.cargo/bin on PATH
```

Linux notes:

- **Non-interactive shells** (CI, agents, `bash -c "..."`, `ssh host cmd`, cron)
  don't run the login's environment-module auto-loads, so they lack the gcc-12.3
  + ccache runtime the prebuilt binaries need. Copy `site-env.sh.example` →
  `site-env.sh` (sourced by `env-linux.sh`; gitignored) and adjust paths.
  Without it a fresh `source env-linux.sh && rb test` fails with
  `verilator_bin: libatomic.so.1: cannot open shared object file`, then
  `make: ccache: Command not found`, then a system g++ 8.5 fallback (issue #6).
  macOS doesn't use `env-linux.sh`/`site-env.sh` at all (Homebrew on PATH).
- gtkwave / graphviz come from the site (system graphviz) — not built here.
  verible IS handled here: `make verible` on Linux downloads the official
  prebuilt linux-static release binary for the pinned tag (no bazel, no
  root needed — site machines like exptw have neither), so `module load
  verible` is no longer used.
- `env-linux.sh` also unsets `VERILATOR_ROOT`, which site verilator modules
  export and which would misdirect this repo's verilator wrapper.
- klayout is not installed (needs root or an AppImage); `rb pnr --gds/--png`
  streamout is unavailable until it is.
- `rb wave` works headless two ways: surfer's `--headless` mode renders
  waveform PNGs with no display at all (`surfer --headless -c <cmds> f.fst`
  with an `export_wave out.png W H` command — see
  rtl-buddy-project-template's `verif/demo_tiny_alu/build_report.py`), and
  the interactive WCP flow runs under Xvfb. Caveat: EDA vendor modules may
  shadow `Xvfb` on PATH (breaking `xvfb-run` with `XOpenDisplayFailed`) —
  start `/usr/bin/Xvfb :99` explicitly and run with `DISPLAY=:99`.

Then put `bin/` on `PATH` — `source env-macos.zsh` / `source env-linux.sh`
do this (plus `VERILATOR_ROOT` hygiene and `RTL_BUDDY_SLANG_PLUGIN`), or
symlink the `bin/` entries from `/usr/local/bin`.
Verify with rtl_buddy: `rb tool-check`.

## What gets built, and why these refs

| Submodule | Source | Pin | Why |
|---|---|---|---|
| `yosys` | rtl-buddy/yosys | branch `rtl-buddy-0.71` (`a5026b6`: v0.71 + patches) | rtl_buddy `docs/concepts/synthesis.md#installing-yosys` mandates the fork: it adds unpacked-struct tolerance, `import pkg::name` lexing, packed-struct-array support. Stock upstream (tested v0.66) fails rtl_buddy synth (`Only PACKED supported`). CMake build (yosys >= 0.67 has no Makefile build), installed into `tools/` |
| `yosys-slang` | rtl-buddy/yosys-slang | branch `rtl-buddy-sv-elab` (`4055765`) | the `sv-elab` revision yosys v0.71 builds in (`2cfcfbe`) plus the fork's SVA support, which upstream still lacks: sequences (`##N`, `##[m:n]`, sequence `and`/`or`), `\|=>`, `disable iff` over the whole property, and `--ignore-unknown-modules` (rtl_buddy's synth parameter probe passes it). Loaded as a plugin, it overrides the built-in `sv-elab` (see rtl_buddy `docs/concepts/fpv.md`) |
| `surfer` | rtl-buddy/surfer | branch `rtl-buddy` | WCP extensions (`set_scope`, `query_variable_values`, `time_unit`) required by `rb wave` / hub bridge; mainline lacks them (see rtl_buddy `docs/install.md`) |
| `verilator` | rtl-buddy/verilator | branch `rtl-buddy-5.054` (`553d2587`: v5.054 + patch) | v5.054 plus one macOS patch: `verilated.mk` adds the Homebrew include/lib dirs for FST tracing's lz4 (Darwin only; without it every `--trace-fst` model compile fails with `lz4.h file not found`) |
| `yices2` | SRI-CSL/yices2 | `560f3b3` (master, 2026-10-15) | sby's default `smtbmc` solver. A master commit, not a tag: it still reports 2.7.0, but the `yices-2.7.0` tag (2025-07, 418 commits older) and 2.6.x do not finish k-induction proofs that this commit closes in about 9 minutes. Check `yices-smt2 --version`'s `Revision:` line, never the number. GMP linked statically |
| `boolector` | Boolector/boolector | `3.2.4` (`393cdfba3`) | sby `smtbmc boolector`; Lingeling, CaDiCaL and btor2tools at the commits Boolector's `contrib/setup-*.sh` pin |
| `sby` | YosysHQ/sby | `v0.66` | official release. Its venv also pins `z3-solver==5.1.0.0`, whose `z3` binary is `bin/z3` |
| `verible` | chipsalliance/verible | `v0.0-4148-g1ea007ec` | upstream release pin (no fork). One version everywhere for `rb verible`/`rb hier`/xeno CST parsing, instead of a drifting brew install (macOS) + site module (Linux). macOS: bazel source build; Linux: the official linux-static release binary for the same tag (site machines have no bazel/root) |
| `OpenROAD` | The-OpenROAD-Project/OpenROAD | `731f8ff5a4` (26Q2+911) | the bare `26Q2` tag crashes `rb power` static/dynamic on macOS; this is the validated commit |
| `veridian` | vivekmalneedi/veridian | master | upstream has no release tags |
| `nextpnr-xilinx` | openXC7/nextpnr-xilinx | `f681eb3a` | OPTIONAL — open FPGA place-and-route for `rb fpga tool: openxc7`; pin matches the openXC7 toolchain-installer's validated ref |
| `prjxray` | openXC7/prjxray | `ce065d47` | OPTIONAL — `fasm2frames`/`xc7frames2bit` for openXC7 bitstreams; installer-validated ref |
| `prjxray-db` | openXC7/prjxray-db | `0.8.2` | OPTIONAL — Xilinx 7-series bitstream database root (`$PRJXRAY_DB_DIR`) |

### Optional: openXC7 FPGA toolchain

`nextpnr-xilinx` + `prjxray` + `prjxray-db` are **not** built by `make all`.
Build the open FPGA flow on demand:

```bash
make openxc7                              # Arty A7-35 chipdb (xc7a35tcsg324-1)
make openxc7 CHIP_PART=xc7a100tcsg324-1   # a different 7-series part
```

This builds `nextpnr-xilinx` (reusing the in-repo `yosys` for `synth_xilinx`),
`prjxray`, and generates the per-part nextpnr chipdb under
`tools/share/nextpnr/chipdb/<part>.bin`. The env scripts export `CHIPDB`
(directory of chipdbs; `rb` resolves `$CHIPDB/<part>.bin`) and
`PRJXRAY_DB_DIR` (needed only for `--bitstream`). macOS notes: nextpnr is
built `BUILD_PYTHON=OFF` (chipdb gen is standalone python; CLI P&R needs no
bindings) so boost-python is never required, and the brew `eigen3` include
dir is passed explicitly because nextpnr's CMakeLists reads the plural
`EIGEN3_INCLUDE_DIRS` that modern `Eigen3Config.cmake` doesn't set.

**Linux (AlmaLinux/Rocky 8.10, gcc 12.3.0): validated end-to-end** — synth →
nextpnr P&R → `fasm2frames` → `xc7frames2bit` produces a valid `xc7a35t`
bitstream for the arty-a35 blinky. It uses the other Linux recipes' `~/.local`
convention for eigen3 and the newer cmake/gmake on `~/.local/bin`, plus four
Linux-specific fixups baked into the recipe (each commented at its site):

- **Boost** — the `~/.local` Boost from OpenROAD's `DependencyInstaller.sh`
  is unusable for nextpnr: it lacks `filesystem`/`program_options` and its
  headers (1.87) and libs (1.89) disagree, so cmake's `FindBoost` rejects the
  whole package. `make openxc7` therefore builds a private **static** Boost
  (the four libs nextpnr links) into `$(BOOST_PREFIX)`
  (`~/.local/opt/boost-nextpnr`, ~5 min, once) and pins cmake to it. Override
  with `make openxc7 BOOST_PREFIX=… BOOST_VERSION=…`.
- **Eigen** — the `~/.local` `Eigen3Config.cmake` sets `EIGEN3_DEFINITIONS`
  to `EIGEN_MPL2_ONLY` *without* a `-D`, so nextpnr's
  `add_definitions(${EIGEN3_DEFINITIONS})` feeds the compiler a bare token;
  the recipe rewrites that one line. Override the eigen include path for a
  system install with `make openxc7 EIGEN3_INC=/usr/include/eigen3`.
- **prjxray venv** — `requirements.txt` has `-e third_party/fasm` / `-e .`
  with relative paths, so pip is run with `CWD=prjxray`.
- **prjxray flock** — `prjxray` `flock()`s every db file it reads, but the
  repo's NFS mount returns `EBADF`; since the db is read-only the recipe
  drops the lock so `fasm2frames` can run.

The gcc-12.3.0 runtime (`libstdc++`) resolves via the baked `LD_RUN_PATH`
from `site-env.sh` (issue #6) — source an env script before building so the
openXC7 binaries pick it up, exactly as for every other tool here.

Non-submodule dirs created by the build (gitignored):

- `tools/` — install prefix for yosys, yices, boolector, verilator
  (`make install`), sby, and the openXC7 nextpnr chipdb
  (`tools/share/nextpnr/chipdb/`).
- `sby-venv/` — python venv (click) backing the sby launcher.
- `openxc7-venv/` — python venv (prjxray requirements) backing `fasm2frames`.

The yosys-slang plugin is not a `bin/` tool. The env scripts export
`RTL_BUDDY_SLANG_PLUGIN=<repo>/yosys-slang/build/slang.so`, which
rtl_buddy >= 6.11.0 uses whenever a project selects `frontend: slang`
without setting `plugin-path`. For shells that don't source an env
script (agents, CI, cron), set the same variable in the consumer
project's gitignored `.rtl-buddy/.env` (`KEY=VALUE` next to
`root_config.yaml`; rb loads it automatically, process env wins). On
older rtl_buddy, point the project config (`plugin-path` /
`plugin_path`) at the path explicitly.

## Not managed here

- klayout — install the [app bundle](https://www.klayout.de/build.html).
- iverilog, graphviz, gtkwave, lcov, marimo — homebrew
  (covered by the brew line above). yices, boolector and z3 are pinned here.
- rtl-buddy-view / rtl-buddy-cdc / rtl-buddy-axi-profiler / info-process —
  per-project python deps (`uv` / pip), not shared binaries.

## Updating a pin

```sh
cd <submodule> && git fetch && git checkout <new-ref>
cd .. && make <tool>
# validate against an rtl_buddy project (see AGENTS.md), then:
git add <submodule> && git commit
```

After moving the `yosys` pin, always rebuild `yosys-slang` too — the plugin
links against the yosys ABI.

## Validation

Every pin in this repo was validated end-to-end against
[rtl-buddy-project-template](https://github.com/rtl-buddy/rtl-buddy-project-template)
and an internal AI project: `rb tool-check`, `rb test`, `rb synth`
(verilog + slang frontends, generic + tech-mapped), `rb cdc`, `rb fpv`,
`rb pnr`, `rb power`, `rb hier`, `rb wave`. See AGENTS.md for the procedure.
