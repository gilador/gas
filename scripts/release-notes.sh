#!/bin/bash
# Prints the release notes for the commits in <from-ref>..<to-ref>, followed by the install section.
set -euo pipefail
cd "$(dirname "$0")/.."

[ $# -eq 2 ] || { echo "usage: scripts/release-notes.sh <from-ref> <to-ref>" >&2; exit 1; }

NEW="" FIXES="" OTHER=""
while IFS= read -r subject; do
  [ -n "$subject" ] || continue
  if [[ "$subject" =~ ^([a-z]+)(\([^\)]*\))?!?:\ (.+)$ ]]; then
    type="${BASH_REMATCH[1]}"
    text="${BASH_REMATCH[3]}"
    first="$(echo "${text:0:1}" | tr '[:lower:]' '[:upper:]')"
    line="- $first${text:1}"
    case "$type" in
      release|docs|build|chore|refactor|test|ci|style) ;;
      feat) NEW+="$line"$'\n' ;;
      fix) FIXES+="$line"$'\n' ;;
      *) OTHER+="- $subject"$'\n' ;;
    esac
  else
    OTHER+="- $subject"$'\n'
  fi
done < <(git log --reverse --format=%s "$1..$2")

if [ -z "$NEW$FIXES$OTHER" ]; then
  echo "Maintenance release, no user-facing changes."
else
  SEP=""
  [ -z "$NEW" ] || { printf "## What's new\n%s" "$NEW"; SEP=$'\n'; }
  [ -z "$FIXES" ] || { printf "%s## Fixes\n%s" "$SEP" "$FIXES"; SEP=$'\n'; }
  [ -z "$OTHER" ] || printf "%s## Other changes\n%s" "$SEP" "$OTHER"
fi

printf '\n---\n\n'
cat scripts/release-notes.md
