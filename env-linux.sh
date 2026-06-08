# env-linux.sh — source this to put the rtl-buddy toolchain on PATH.
#   source <this repo>/env-linux.sh
# May also be sourced through a symlink (e.g. a per-project project_setup.sh
# that links here); readlink -f resolves to this repo regardless.
#
# Order matters: this repo's bin/ first (pinned yosys/verilator/surfer/sby),
# then ~/.local/bin (z3, yices, iverilog, lcov, bison, OpenROAD deps from
# install-prereqs-linux.sh), then ~/.cargo/bin (rust toolchain).
_RB_TOOLS_SRC="$(readlink -f "${BASH_SOURCE[0]:-$0}")"
_RB_TOOLS_ROOT="$(cd "$(dirname "$_RB_TOOLS_SRC")" && pwd)"
export PATH="$_RB_TOOLS_ROOT/bin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

# Site environment-module setups commonly export VERILATOR_ROOT for a
# foreign verilator install. Our verilator is `make install`ed, so it
# resolves its data dir from a compiled-in root (confirm with
# `verilator --getenv VERILATOR_ROOT`). Per the Verilator manual an
# installed verilator must NOT have VERILATOR_ROOT set — that variable is
# only for running from a build/kit tree, and a stale site value would
# misdirect the wrapper. So clear it and let the embedded root win; do not
# set it to this repo.
unset VERILATOR_ROOT

# Machine-specific additions (e.g. a verible module dir on PATH, a SystemC
# lib64 on LD_LIBRARY_PATH) live in an untracked sibling site-env.sh —
# same user-local convention as the top-level *.zsh scripts (AGENTS.md).
[ -f "$_RB_TOOLS_ROOT/site-env.sh" ] && . "$_RB_TOOLS_ROOT/site-env.sh"
unset _RB_TOOLS_ROOT _RB_TOOLS_SRC
