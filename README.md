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
brew tap chipsalliance/verible   # verible is not in homebrew-core
brew install bison flex cmake llvm boost eigen spdlog or-tools tcl-tk@8 swig \
             gtkwave graphviz lcov verible icarus-verilog z3 yices2 uv make
# brew `make` (GNU make 4.x) is required by `make verilator`: Apple's make
# 3.81 mishandles verilator's .SECONDARY intermediates and silently never
# links verilator_coverage_bin_dbg (install then fails with Error 71).
# uv (rtl_buddy's package manager) is also required by `make sby`: it builds
# sby's venv on uv's CPython 3.11 — the same interpreter rb runs on, instead of
# the ambient python3 (see SBY_PYTHON in the Makefile). Usually already present
# wherever rb is installed.
# Rust toolchain (surfer, veridian): https://rustup.rs
# OpenROAD's lemon/cudd deps (once):
#   cd OpenROAD && ./etc/DependencyInstaller.sh -prefix $HOME/.local && cd ..

make all          # everything (OpenROAD takes hours)
# or individually, e.g.:
make yosys yosys-slang verilator surfer sby

source env-macos.zsh  # puts bin/ on PATH, unsets VERILATOR_ROOT,
                      # exports RTL_BUDDY_SLANG_PLUGIN
```

## Quick start (Linux — validated on Rocky 8.10, no root)

Assumes a toolchain with gcc >= 12 and cmake >= 3.16 on PATH (e.g. via
`module load gcc cmake`) plus system `tcl-devel readline-devel zlib-devel
libffi-devel gmp-devel`. Everything else installs to `~/.local` / `~/.cargo`:

```sh
git clone --recursive https://github.com/rtl-buddy/rtl-buddy-tools.git
cd rtl-buddy-tools

# Rust toolchain (surfer, veridian):
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
# bison 3.8, gperf, help2man, yaml-cpp, z3, yices2, iverilog, lcov, gmake alias:
./install-prereqs-linux.sh
# OpenROAD's boost/eigen/lemon/cudd/or-tools/swig deps (once):
#   cd OpenROAD && ./etc/DependencyInstaller.sh -common -prefix=$HOME/.local && cd ..

cp site-env.sh.example site-env.sh   # machine-local env (gcc/ccache runtime, verible, SystemC, node) — adjust paths
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
- verible / gtkwave / graphviz come from the site (`module load verible`,
  system graphviz) — not built here.
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
| `yosys` | rtl-buddy/yosys | branch `rtl-buddy` (v0.64 + patches) | rtl_buddy `docs/concepts/synthesis.md#installing-yosys` mandates the fork: it adds unpacked-struct tolerance, `import pkg::name` lexing, packed-struct-array support. Stock upstream (tested v0.66) fails rtl_buddy synth (`Only PACKED supported`) |
| `yosys-slang` | rtl-buddy/yosys-slang | branch `rtl-buddy` | SVA implication lowering for `rb fpv frontend: slang`; switch to povik master once [povik/yosys-slang#317](https://github.com/povik/yosys-slang/pull/317) merges (see rtl_buddy `docs/concepts/fpv.md`) |
| `surfer` | rtl-buddy/surfer | branch `rtl-buddy` | WCP extensions (`set_scope`, `query_variable_values`, `time_unit`) required by `rb wave` / hub bridge; mainline lacks them (see rtl_buddy `docs/install.md`) |
| `verilator` | rtl-buddy/verilator | branch `rtl-buddy` (v5.048 + patch) | v5.048 + backport of the V3TSP variable-ordering data-race fix (upstream PR #7752 / issues #7194, #5756): the global edge-id counter races under `--threads>1 -j>1` → `V3TSP.cpp: No unmarked edges found in tour`. No released verilator (≤ v5.048) has the fix; upstream `master`/5.049-devel removed V3TSP entirely. Re-point to a v5.049 tag once released |
| `sby` | YosysHQ/sby | `v0.66` | official release |
| `OpenROAD` | The-OpenROAD-Project/OpenROAD | `731f8ff5a4` (26Q2+911) | the bare `26Q2` tag crashes `rb power` static/dynamic on macOS; this is the validated commit |
| `veridian` | vivekmalneedi/veridian | master | upstream has no release tags |

Non-submodule dirs created by the build (gitignored):

- `tools/` — install prefix for verilator (`make install`) and sby.
- `sby-venv/` — python venv (click) backing the sby launcher.

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
- iverilog, verible, z3, yices, graphviz, gtkwave, lcov, marimo — homebrew
  (covered by the brew line above).
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
