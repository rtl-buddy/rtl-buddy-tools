# env-macos.zsh — source this to put the rtl-buddy toolchain on PATH (zsh).
#   source <this repo>/env-macos.zsh
# May also be sourced through a symlink (e.g. a per-project project_setup
# script that links here); readlink -f (macOS >= 12.3) resolves to this
# repo regardless.
#
# Unlike Linux, the prerequisites (z3, yices, verible, iverilog, ...) come
# from Homebrew and are already on PATH; this script only adds the pinned
# in-repo tools plus the env knobs rb needs beyond PATH.
_RB_TOOLS_SRC="${(%):-%N}"
_RB_TOOLS_ROOT="$(cd "$(dirname "$(readlink -f "$_RB_TOOLS_SRC")")" && pwd)"
export PATH="$_RB_TOOLS_ROOT/bin:$PATH"

# Same rationale as env-linux.sh: per the Verilator manual an installed
# verilator must NOT have VERILATOR_ROOT set — the binary's embedded root
# wins; a stale value would misdirect the wrapper.
unset VERILATOR_ROOT

# yosys-slang's slang.so is a plugin, not a bin/ executable, so PATH cannot
# provide it. rtl_buddy (rtl-buddy/rtl_buddy 307 and later) falls back to
# this variable when a project selects `frontend: slang` without setting
# `plugin-path`, keeping project configs free of machine-specific paths.
export RTL_BUDDY_SLANG_PLUGIN="$_RB_TOOLS_ROOT/yosys-slang/build/slang.so"

unset _RB_TOOLS_ROOT _RB_TOOLS_SRC
