#!/usr/bin/env bash
# Shared helpers for the Windows startup measurements. Sourced.

# Wall-clock seconds with sub-second precision (Git Bash and bash 5 both have it).
now() { date +%s.%N; }
elapsed() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.2f", b - a }'; }
median() { sort -n | awk '{ v[NR] = $1 } END { if (NR) print v[int((NR + 1) / 2)]; else print "n/a" }'; }

# Extract one ref's scripts/ into a fresh throwaway skill dir and init its db.
# usage: make_skill <repo> <ref> <dest>
make_skill() {
  local repo="$1" ref="$2" dest="$3"
  mkdir -p "$dest"/{scripts,db,teams,run}
  git -C "$repo" archive "$ref" scripts | tar -x -C "$dest"
  chmod +x "$dest"/scripts/*.sh "$dest"/scripts/drivers/types/codex/*.sh 2>/dev/null || true
  AGMSG_STORAGE_PATH="$dest/store" bash "$dest/scripts/internal/init-db.sh" >/dev/null 2>&1 || true
}

summary() { if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then printf '%s\n' "$*" >> "$GITHUB_STEP_SUMMARY"; fi; }
