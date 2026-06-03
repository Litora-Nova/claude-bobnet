#!/usr/bin/env bash
# Bug-/Update-Check (cron): npm-audit (high+crit) je Repo aus DEV_TEAM_REPOS.
# Env: STANDUP_DIR, DEV_TEAM_REPOS (Space-Liste relativ zu ROOT).
set -uo pipefail
export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" >/dev/null 2>&1
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$DIR/../.." && pwd)"; ST="${STANDUP_DIR:-$ROOT/standup}"
ts="$(date '+%Y-%m-%d %H:%M')"; problems=0; rep="## Bug-/Update-Check $ts"
for repo in ${DEV_TEAM_REPOS:-acme_backend acme_frontend acme_website}; do
  dd="$ROOT/$repo"; [ -d "$dd/.git" ] || continue
  if [ -d "$dd/node_modules" ]; then
    hi="$(cd "$dd" && npm audit --omit=dev --json 2>/dev/null | python3 -c "import sys,json
try:
 v=json.load(sys.stdin).get('metadata',{}).get('vulnerabilities',{}); print(v.get('high',0)+v.get('critical',0))
except: print(0)" 2>/dev/null || echo 0)"
    rep="$rep
- $repo: npm high+crit=${hi:-?}"; [ "${hi:-0}" -gt 0 ] 2>/dev/null && problems=$((problems+1))
  else
    rep="$rep
- $repo: Deps nicht installiert -> Test/Audit uebersprungen"
  fi
done
rep="$rep
(Voll-Coverage braucht: bundle install BE [ruby 3.3.5 vs 3.4.2 klaeren] + npm install FE/Web.)"
printf '%s\n\n' "$rep" >> "$ST/_bugs.md"
[ "$problems" -gt 0 ] && "$ST/scut.sh" "Bug-Check $ts: $problems Repo(s) mit High/Crit — siehe _bugs.md" urgent >/dev/null 2>&1
echo "[bugcheck] ok $ts (problems=$problems)"
