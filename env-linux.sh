# env-linux.sh — source this to put the rtl-buddy toolchain on PATH.
#   source <this repo>/env-linux.sh
#
# Order matters: this repo's bin/ first (pinned yosys/verilator/surfer/sby),
# then ~/.local/bin (z3, yices, iverilog, lcov, bison, OpenROAD deps from
# install-prereqs-linux.sh), then ~/.cargo/bin (rust toolchain).
_RB_TOOLS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
export PATH="$_RB_TOOLS_ROOT/bin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

# Site environment-module setups commonly export VERILATOR_ROOT for a
# foreign verilator install; that would misdirect this repo's verilator
# wrapper (our verilator is `make install`ed with its own embedded root).
unset VERILATOR_ROOT

# Machine-specific additions (e.g. a verible module dir on PATH, a SystemC
# lib64 on LD_LIBRARY_PATH) live in an untracked sibling site-env.sh —
# same user-local convention as the top-level *.zsh scripts (AGENTS.md).
[ -f "$_RB_TOOLS_ROOT/site-env.sh" ] && . "$_RB_TOOLS_ROOT/site-env.sh"
unset _RB_TOOLS_ROOT
