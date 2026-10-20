#!/usr/bin/env bash
# Static checks: shellcheck on all shell scripts, bash -n, actionlint on workflows, JSON validity.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_DIR"
mapfile -t scripts < <(grep -rlE '^#!.*(ba)?sh' scripts overlay/usr/local/bin overlay/usr/share/kiosk 2>/dev/null | sort)
log "bash -n / shellcheck on ${#scripts[@]} scripts"
for s in "${scripts[@]}"; do bash -n "$s"; done
if command -v shellcheck >/dev/null; then shellcheck -x -s bash -S warning "${scripts[@]}"; else warn "shellcheck not installed"; fi
log "json"
while IFS= read -r j; do jq -e . "$j" >/dev/null || die "invalid JSON: $j"; done < <(find overlay -name '*.json')
if command -v actionlint >/dev/null; then log "actionlint"; actionlint; else warn "actionlint not installed"; fi
log "lint OK"
