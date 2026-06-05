# AGENTS.md — rtl-buddy tools installer repo

Guidance for AI agents (and humans) working in this repository.

## What this repo is

A macOS + Linux "installer" superproject for the external EDA tools that
[rtl_buddy](https://github.com/rtl-buddy/rtl_buddy) shells out to. It exists so
tool builds live in ONE place with pinned, validated refs — not scattered
across per-user workspaces. It is consumed two ways:

1. `bin/` on `PATH` (macOS: or `/usr/local/bin` symlinks into `bin/`;
   Linux: `source env-linux.sh`).
2. Project configs pointing at `yosys-slang/build/slang.so` (`plugin-path`).

## Layout

```
Makefile                  # the build recipe per tool — the source of truth
                          #   (recipes branch on `uname -s`: Darwin / Linux)
bin/                      # committed relative symlinks to every built binary
<submodules>              # yosys, yosys-slang, verilator, surfer, sby, OpenROAD, veridian
tools/                    # gitignored install prefix (verilator, sby)
sby-venv/                 # gitignored python venv for the sby launcher
install-prereqs-linux.sh  # Linux: user-space deps brew provides on macOS (-> ~/.local)
env-linux.sh              # Linux: PATH setup + VERILATOR_ROOT unset; sources site-env.sh
```

Untracked `*.zsh` scripts and `site-env.sh` at the top level are user-local
(machine-specific symlink/PATH management). Leave them untracked; do not
commit, generalize, or delete them.

## Ground rules

1. **Pins are deliberate.** Three submodules intentionally point at
   `rtl-buddy/*` forks, NOT upstream (yosys, yosys-slang, surfer). The
   rationale lives in README.md and in rtl_buddy's own docs
   (`docs/concepts/synthesis.md`, `docs/concepts/fpv.md`, `docs/install.md`).
   Do not "upgrade" them to upstream releases without re-running the
   validation below — stock upstream is known to break rtl_buddy flows
   (yosys v0.66: `Only PACKED supported`; mainline surfer: missing WCP
   commands; povik yosys-slang master: no SVA `|->` lowering until
   povik/yosys-slang#317 merges).
2. **rtl_buddy docs are the authority** for which repo/branch each tool comes
   from. When a fork's reason disappears upstream (e.g. #317 merges), the
   docs flip first; follow them, re-validate, then move the pin here.
3. **yosys and yosys-slang move together.** The plugin links against the
   yosys ABI — after changing the yosys pin or rebuilding yosys, always
   `make yosys-slang` (the Makefile target does a full plugin rebuild only if
   you `rm -rf yosys-slang/build` first; do that across ABI changes).
4. **The OpenROAD cmake flags are all load-bearing on macOS.** Known failure
   modes if removed:
   - no `CMAKE_DISABLE_FIND_PACKAGE_Qt5` → broken brew Qt5 plugin refs abort configure
   - system `/usr/bin/bison` (2.3) picked up → `def.y syntax error`
   - Apple `/usr/bin/flex` + brew FlexLexer.h → `LexerInput does not match any
     declaration` (size_t vs int); use the brew flex *pair* (binary + header)
   - no `BOOST_STACKTRACE_GNU_SOURCE_NOT_REQUIRED` → `_Unwind_Backtrace` error
   - no explicit `-L` linker dirs → `ld: library 'zstd' not found` in test bins
5. **Don't pin OpenROAD to a bare quarterly tag without testing `rb power`.**
   The `26Q2` tag built fine but crashed power analysis; the pinned commit is
   the validated one.
6. **sby quirks:** the launcher must be invoked through its real path (bin/sby
   is an exec wrapper, not a symlink) and the Makefile passes
   `YOSYS_RELEASE_VERSION` explicitly because `git describe` inside sby's own
   Makefile resolves empty under an absorbed submodule gitdir.
7. **macOS and Linux recipes coexist; don't cross-contaminate.** The
   Makefile branches on `uname -s` — when touching one OS's recipe, leave
   the other branch byte-identical (the Darwin recipe is the original,
   validated one). Linux-only failure modes the recipe flags guard against
   (validated on Rocky 8.10, no root):
   - system bison 3.0.4 → yosys `require bison 3.6`; verilator man pages
     also need `help2man` (both via install-prereqs-linux.sh → ~/.local)
   - system `gmake` 4.2.1 picked up by cmake → `invalid --jobserver-auth
     string 'fifo:...'` under make ≥ 4.4 (the prereq script aliases gmake)
   - in-tree `yosys-config --cxxflags` emits its baked-in `/usr/local`
     include dir → yosys-slang needs `-DCMAKE_CXX_FLAGS=-I$(ROOT)/yosys`
   - or-tools' bundled Boost-1.87 cmake configs shadow the installer-built
     1.89 → pin `Boost_DIR`; bare `-lyaml-cpp` test links need explicit
     `-L ~/.local/lib{,64}`
   - site modules export `VERILATOR_ROOT` → must be unset to build AND run
     (env-linux.sh does this)
8. **Moving a Linux checkout re-embeds paths.** `tools/bin/sby` (venv
   shebang) and the verilator install (configure-time prefix) hardcode the
   absolute repo path: after a move, `rm -rf sby-venv && make sby` and
   `make verilator`, and delete stale verilator `obj_dir*` caches in
   consuming projects (their generated makefiles point at the old prefix).
   Prefer the canonical physical path (not a symlinked `$HOME` view) so
   embedded paths work for every user of a shared checkout.
9. **Commit style:** a pin bump is one commit containing the submodule pointer,
   any Makefile/README/AGENTS.md updates it forces, and a body that names the
   validation performed. Never commit `tools/`, `sby-venv/`, or build outputs.

## Validation procedure (run before committing any pin change)

With this repo's `bin/` first on `PATH`, in an rtl_buddy project checkout
(rtl-buddy-project-template or similar):

```sh
rb tool-check                      # everything resolves + versions parse
rb test            # (verif suite)  verilator compile + sim
rb synth-regression                # yosys generic synth
rb synth   # a tech-mapped + a frontend:slang entry (needs PDK download + slang.so)
rb cdc                             # yosys-backed CDC lint — compare counts to baseline
rb fpv                             # sby + solver, expect proved
rb pnr -l 1000 && rb power -l 1000 # OpenROAD place&route + power (static/dynamic)
rb hier                            # verible + rtl-buddy-view
```

A result is a regression only if it differs from the same command run on the
previously pinned tools. Pre-existing failures (missing PDK before download,
project-local stale paths, `power postpnr`) are not.

## Gotchas inherited from the consolidation

- rtl_buddy projects commonly resolve `plugin_path: "../yosys-slang/build/slang.so"`
  against the *project root* — i.e. they expect a workspace-sibling
  `yosys-slang`. When consolidating a workspace, leave a symlink
  `<workspace>/yosys-slang -> <this repo>/yosys-slang`.
- An in-tree yosys build embeds `/usr/local/share/yosys` as datdir but
  resolves its real share dir from the binary's location — symlinking the
  binary is fine; copying it is not.
- `verilator` must be `./configure --prefix=<this repo>/tools && make install`;
  the wrapper hardcodes configure-time paths, so symlinking an uninstalled
  in-tree build breaks data-file resolution.
