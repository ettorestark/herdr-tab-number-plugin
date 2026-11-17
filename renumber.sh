#!/bin/sh
# Label every tab "N. name", N = its position in the workspace (1..n).
# Idempotent: only tabs whose label is out of date get renamed, so the
# tab.renamed events this script causes settle after one extra pass.
set -u
PATH="$PATH:/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin"
herdr="${HERDR_BIN_PATH:-herdr}"

# Serialise concurrent hook runs (several events can fire at once).
lock="${HERDR_PLUGIN_STATE_DIR:-${TMPDIR:-/tmp}}/tab-number.lock"
mkdir -p "$(dirname "$lock")" 2>/dev/null
i=0
until mkdir "$lock" 2>/dev/null; do
  i=$((i + 1))
  [ "$i" -gt 50 ] && { rmdir "$lock" 2>/dev/null; i=0; }  # stale lock
  sleep 0.1
done
trap 'rmdir "$lock" 2>/dev/null' EXIT INT TERM

# An unnamed tab (default label = a bare number, or the bare "N."
# set by an earlier pass) is shown as just "N.".
"$herdr" workspace list | jq -r '.result.workspaces[].workspace_id' |
while IFS= read -r ws; do
  "$herdr" tab list --workspace "$ws" |
    jq -r '.result.tabs | to_entries[]
      | .value.label as $l
      | (if ($l | test("^[0-9]+\\.?$"))
         then "" else ($l | sub("^[0-9]+\\. "; "")) end) as $name
      | (if $name == "" then "\(.key + 1)." else "\(.key + 1). \($name)" end) as $want
      | select(.value.label != $want)
      | [.value.tab_id, $want] | @tsv' |
  while IFS="$(printf '\t')" read -r tab label; do
    "$herdr" tab rename "$tab" "$label" >/dev/null
  done
done
