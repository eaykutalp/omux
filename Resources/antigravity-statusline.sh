#!/bin/sh

# Antigravity sends the active conversation as JSON on stdin. omux supplies a
# per-terminal OMUX_TAB_ID so multiple tabs in one workspace do not collide.
payload=$(/bin/cat)
tab_id=${OMUX_TAB_ID:-}
dir="$HOME/Library/Application Support/omux/antigravity-conversations"
/bin/mkdir -p "$dir"
/usr/bin/printf '%s' "$payload" > "$dir/usage.json"
if [ -n "$tab_id" ]; then
  conversation_id=$(printf '%s' "$payload" | /usr/bin/python3 -c 'import json,sys
try:
    value=json.load(sys.stdin).get("conversation_id", "")
    print(value if isinstance(value, str) else "")
except Exception:
    print("")')
  if [ -n "$conversation_id" ]; then
    /usr/bin/printf '%s\n' "$conversation_id" > "$dir/$tab_id"
  fi
fi

# Keep the built-in status line visible when this collector is stacked below it.
