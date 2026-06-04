# claude_shared

Canonical, consolidated builds of the EDA tools that [rtl_buddy](https://github.com/rtl-buddy/rtl_buddy)
and its ecosystem depend on. Previously these were scattered across
`~/Work/claude_2`, `~/Work/hern_claude_*`, etc.; this superproject is the
single place they are cloned, pinned, and built.

## Layout

| Submodule | Source | Pin | Why |
|---|---|---|---|
| `yosys` | rtl-buddy/yosys | branch `rtl-buddy` (v0.64 + patches) | rtl_buddy `docs/concepts/synthesis.md#installing-yosys` mandates the fork: it adds unpacked-struct tolerance, `import pkg::name` lexing, packed-struct-array support. Stock `v0.66` was tried and fails template synth demos (`Only PACKED supported`) |
| `yosys-slang` | rtl-buddy/yosys-slang | branch `rtl-buddy` | SVA implication lowering for `rb fpv frontend: slang`; switch to povik master once [povik/yosys-slang#317](https://github.com/povik/yosys-slang/pull/317) merges (see rtl_buddy `docs/concepts/fpv.md`) |
| `verilator` | verilator/verilator | `v5.048` | official release |
| `surfer` | rtl-buddy/surfer | branch `rtl-buddy` | WCP extensions (`set_scope`, `query_variable_values`, `time_unit`) required by `rb wave` / hub bridge; mainline lacks them (see rtl_buddy `docs/install.md`) |
| `sby` | YosysHQ/sby | `v0.66` | official release |
| `OpenROAD` | The-OpenROAD-Project/OpenROAD | `26Q2` | latest quarterly tag |
| `veridian` | vivekmalneedi/veridian | master | upstream has no release tags |

Non-submodule dirs (gitignored):

- `tools/` — install prefix for verilator (`make install`) and sby.
- `sby-venv/` — python venv (click) backing the sby launcher.

`bin/` — committed relative symlinks to every built binary. Point
`/usr/local/bin` entries (or your `PATH`) here; see `repoint_usr_local_bin.zsh`.

## Building

```sh
make all          # everything (OpenROAD takes hours)
make yosys yosys-slang verilator surfer veridian sby openroad   # individually
```

Prereqs (homebrew): `bison flex cmake llvm boost eigen spdlog or-tools tcl-tk@8 swig`
plus a Rust toolchain for surfer/veridian. OpenROAD's remaining deps (cudd,
lemon) are expected under `~/.local` (installed once via OpenROAD's
`DependencyInstaller.sh -prefix ~/.local`).

## Not managed here

- klayout — `/Applications/KLayout` app bundle.
- iverilog, verible, z3, yices, graphviz, gtkwave, lcov, marimo — homebrew.
- rtl-buddy-view / rtl-buddy-cdc / axi-profiler / info-process — per-project
  dev repos (uv tool installs), not shared binaries.

## Updating a pin

```sh
cd <submodule> && git fetch && git checkout <new-tag>
cd .. && make <tool> && git add <submodule> && git commit
```
