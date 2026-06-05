#!/bin/zsh
# Remove the old per-workspace tool builds superseded by claude_shared.
#
#   zsh cleanup_old_builds.zsh            # dry run: report only, delete nothing
#   zsh cleanup_old_builds.zsh --delete   # actually remove
#
# Safety rails:
#   - aborts unless /usr/local/bin/yosys resolves into claude_shared and runs
#   - a git repo with uncommitted changes or unpushed commits is SKIPPED
#   - symlinks elsewhere in ~/Work that point into a candidate are reported
#     (they would dangle) — repoint them to claude_shared first
#
# Deliberately NOT listed (active dev clones, not just builds):
#   claude_1/surfer, claude_1/surfer_1   — surfer fork dev work
#   claude_2/gtkwave                     — not part of the consolidation (brew gtkwave is used)
#   hern_claude_1/systemc*               — SystemC is not a claude_shared tool

set -u
DELETE=0
[[ "${1:-}" == "--delete" ]] && DELETE=1

W=/Users/zloh/Work
candidates=(
  # old yosys builds
  $W/claude_2/yosys-pr1
  $W/claude_2/yosys
  $W/claude_2/yosys-main-update
  $W/hern_claude_2/yosys
  # old yosys-slang builds
  $W/claude_2/yosys-slang
  $W/claude_2/povik-yosys-slang
  $W/claude_3/yosys-slang
  $W/hern_claude_4/yosys-slang
  # old verilator build trees (binaries were copied to /usr/local, now replaced)
  $W/claude_2/verilator_v5_0_42
  $W/claude_2/verilator_v5_0_48
  $W/hern_claude_1/verilator_v5_042
  $W/hern_claude_1/verilator_v5_048
  # old OpenROAD builds
  $W/claude_2/OpenROAD
  $W/hern_claude_2/OpenROAD
  # old veridian build
  $W/claude_2/veridian
  # old sby clone + venv
  $W/hern_claude_1/sby
  $HOME/.local/share/sby-venv
)

# ---- sanity: claude_shared must be live --------------------------------
if [[ "$(readlink /usr/local/bin/yosys 2>/dev/null)" != /Users/zloh/Work/claude_shared/* ]]; then
  echo "ABORT: /usr/local/bin/yosys does not point into claude_shared — run repoint_usr_local_bin.zsh first."
  exit 1
fi
if ! /usr/local/bin/yosys -V >/dev/null 2>&1; then
  echo "ABORT: /usr/local/bin/yosys does not run."
  exit 1
fi
echo "sanity ok: $( /usr/local/bin/yosys -V )"
echo

# ---- one-shot symlink inventory of ~/Work ------------------------------
# (single find pass; per-candidate grep against it is then cheap)
linkmap=$(mktemp)
find $W -maxdepth 7 -type l 2>/dev/null | while read -r l; do
  printf '%s\t%s\n' "$l" "$(readlink "$l")"
done > $linkmap

# ---- per-candidate checks ----------------------------------------------
total_kb=0
removable=()
for d in $candidates; do
  [[ -e $d ]] || { echo "GONE  $d (already removed)"; continue; }

  # git safety: skip repos with local-only work.
  # Untracked files alone (build outputs, helper scripts) do NOT block removal;
  # modified/staged tracked files or unpushed commits do.
  note=""
  if [[ -e $d/.git ]]; then
    if [[ -n "$(git -C $d status --porcelain 2>/dev/null | grep -v '^??' | head -1)" ]]; then
      echo "SKIP  $d — modified tracked files (local patch? review by hand):"
      git -C $d status --porcelain 2>/dev/null | grep -v '^??' | sort -u | head -3 | sed 's/^/        /'
      continue
    fi
    if [[ -n "$(git -C $d log --branches --not --remotes --oneline 2>/dev/null | head -1)" ]]; then
      echo "SKIP  $d — has unpushed commits (review by hand)"
      continue
    fi
    [[ -n "$(git -C $d status --porcelain 2>/dev/null | head -1)" ]] && note=" (untracked build files only)"
  fi

  # dangling-symlink consumers: anything in ~/Work pointing into this dir
  consumers=$(awk -F'\t' -v d="$d" 'index($2, d) == 1 && index($1, d) != 1 {print $1}' $linkmap | head -5)
  if [[ -n "$consumers" ]]; then
    echo "SKIP  $d — symlinks still point here, repoint them to claude_shared first:"
    echo "$consumers" | sed 's/^/        /'
    continue
  fi

  kb=$(du -sk $d 2>/dev/null | awk '{print $1}')
  total_kb=$(( total_kb + kb ))
  removable+=($d)
  printf "RM    %-55s %6.1f GB%s\n" $d $(( kb / 1048576.0 )) $note
done

rm -f $linkmap
echo
printf "reclaimable: %.1f GB in %d dirs\n" $(( total_kb / 1048576.0 )) ${#removable}

if (( DELETE )); then
  echo
  for d in $removable; do
    echo "deleting $d ..."
    rm -rf $d
    # rtl-buddy projects resolve `../yosys-slang/build/slang.so` against
    # their workspace root — leave a symlink to claude_shared in place of
    # any removed yosys-slang clone so those configs keep working.
    if [[ ${d:t} == yosys-slang ]]; then
      ln -s /Users/zloh/Work/claude_shared/yosys-slang $d
      echo "        replaced with symlink -> claude_shared/yosys-slang"
    fi
  done
  echo "done."
  echo "NOTE: /usr/local/share/verilator (stale, root-owned) needs:  sudo rm -rf /usr/local/share/verilator"
else
  echo
  echo "Dry run only. Re-run with --delete to remove the dirs marked RM."
  echo "NOTE: /usr/local/share/verilator (stale, root-owned) needs:  sudo rm -rf /usr/local/share/verilator"
fi
