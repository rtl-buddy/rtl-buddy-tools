# rtl-buddy tools — macOS installer

One repo that clones, pins, and builds every external EDA tool
[rtl_buddy](https://github.com/rtl-buddy/rtl_buddy) depends on. Each tool is a
git submodule at a validated ref; the top-level `Makefile` encodes the exact
macOS build recipe; `bin/` ends up with a symlink to every binary.

## Quick start

```sh
git clone --recursive https://github.com/rtl-buddy/rtl-buddy-tools.git
cd rtl-buddy-tools

# prerequisites — Apple Silicon or Intel (brew prefix auto-detected);
# Xcode CLT assumed (xcode-select --install)
brew tap chipsalliance/verible   # verible is not in homebrew-core
brew install bison flex cmake llvm boost eigen spdlog or-tools tcl-tk@8 swig \
             gtkwave graphviz lcov verible icarus-verilog z3 yices2
# Rust toolchain (surfer, veridian): https://rustup.rs
# OpenROAD's lemon/cudd deps (once):
#   cd OpenROAD && ./etc/DependencyInstaller.sh -prefix $HOME/.local && cd ..

make all          # everything (OpenROAD takes hours)
# or individually, e.g.:
make yosys yosys-slang verilator surfer sby
```

Then put `bin/` on `PATH`, or symlink its entries from `/usr/local/bin`.
Verify with rtl_buddy: `rb tool-check`.

## What gets built, and why these refs

| Submodule | Source | Pin | Why |
|---|---|---|---|
| `yosys` | rtl-buddy/yosys | branch `rtl-buddy` (v0.64 + patches) | rtl_buddy `docs/concepts/synthesis.md#installing-yosys` mandates the fork: it adds unpacked-struct tolerance, `import pkg::name` lexing, packed-struct-array support. Stock upstream (tested v0.66) fails rtl_buddy synth (`Only PACKED supported`) |
| `yosys-slang` | rtl-buddy/yosys-slang | branch `rtl-buddy` | SVA implication lowering for `rb fpv frontend: slang`; switch to povik master once [povik/yosys-slang#317](https://github.com/povik/yosys-slang/pull/317) merges (see rtl_buddy `docs/concepts/fpv.md`) |
| `surfer` | rtl-buddy/surfer | branch `rtl-buddy` | WCP extensions (`set_scope`, `query_variable_values`, `time_unit`) required by `rb wave` / hub bridge; mainline lacks them (see rtl_buddy `docs/install.md`) |
| `verilator` | verilator/verilator | `v5.048` | official release |
| `sby` | YosysHQ/sby | `v0.66` | official release |
| `OpenROAD` | The-OpenROAD-Project/OpenROAD | `731f8ff5a4` (26Q2+911) | the bare `26Q2` tag crashes `rb power` static/dynamic on macOS; this is the validated commit |
| `veridian` | vivekmalneedi/veridian | master | upstream has no release tags |

Non-submodule dirs created by the build (gitignored):

- `tools/` — install prefix for verilator (`make install`) and sby.
- `sby-venv/` — python venv (click) backing the sby launcher.

The yosys-slang plugin is not a `bin/` tool — point project configs
(`plugin-path` / `plugin_path`) at `<repo>/yosys-slang/build/slang.so`.

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
