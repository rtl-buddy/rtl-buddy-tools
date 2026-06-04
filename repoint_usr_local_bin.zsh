#!/bin/zsh
# Repoint /usr/local/bin (and ~/.local/bin/sby) at the consolidated
# claude_shared builds. Run AFTER `make all` has succeeded and the
# end-to-end rtl_buddy checks pass.
#
#   sudo zsh /Users/zloh/Work/claude_shared/repoint_usr_local_bin.zsh
#
# Replaces:
#   yosys*          -> was claude_2/yosys-pr1 symlinks
#   verilator*      -> was real binaries copied into /usr/local/bin
#   surfer, surver  -> was claude_1/surfer symlinks
#   openroad        -> was claude_2/OpenROAD symlink
#   veridian        -> was claude_2/veridian symlink
# Leaves alone: klayout (app bundle), homebrew tools.

set -e
SHARED=/Users/zloh/Work/claude_shared/bin

tools=(
  yosys yosys-abc yosys-config yosys-filterlib yosys-smtbmc yosys-witness
  verilator verilator_bin verilator_bin_dbg verilator_coverage
  verilator_coverage_bin_dbg verilator_gantt verilator_profcfunc
  surfer surver openroad veridian
)

for t in $tools; do
  src=$SHARED/$t
  dst=/usr/local/bin/$t
  if [[ ! -e $src ]]; then
    echo "SKIP $t — $src does not resolve (not built yet?)"
    continue
  fi
  [[ -e $dst || -L $dst ]] && rm -f $dst
  ln -s $src $dst
  echo "LINK $dst -> $src"
done

# Stale data dir from the old `make install` of verilator into /usr/local —
# the new wrapper resolves claude_shared/tools/share instead.
if [[ -d /usr/local/share/verilator ]]; then
  echo "NOTE: /usr/local/share/verilator is stale (safe to remove):"
  echo "      rm -rf /usr/local/share/verilator"
fi

# sby lives in ~/.local/bin (no sudo needed for this part, but harmless).
u=${SUDO_USER:-$USER}
sby_dst=$(eval echo ~$u)/.local/bin/sby
if [[ -e $SHARED/sby ]]; then
  rm -f $sby_dst
  ln -s $SHARED/sby $sby_dst
  echo "LINK $sby_dst -> $SHARED/sby"
  echo "NOTE: old venv ~/.local/share/sby-venv is now unused (safe to remove)."
fi

echo "done."
