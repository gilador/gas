#!/bin/bash
# Tokens bridge: saves the Claude Code status-line JSON for the Tokens app, then runs the previous status line command.
dir="$HOME/Library/Application Support/Tokens"
input=$(cat)
umask 077
if [ -n "$input" ]; then
  printf '%s' "$input" > "$dir/claude_statusline.json.tmp" && mv -f "$dir/claude_statusline.json.tmp" "$dir/claude_statusline.json"
fi
if [ -s "$dir/claude-bridge.prev" ]; then
  prev=$(cat "$dir/claude-bridge.prev")
  printf '%s' "$input" | bash -c "$prev"
fi
