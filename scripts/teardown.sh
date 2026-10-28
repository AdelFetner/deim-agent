#!/usr/bin/env bash
# Stops the demo.
#   teardown.sh              stop + DELETE all GitLab data (asks for confirmation)
#   teardown.sh --keep-data  stop containers, keep volumes (fast restart later)
#   teardown.sh --yes        skip confirmation
# NEVER run a full teardown between rehearsal and demo (rehearsal MRs live in the volumes).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; exit "${1:-0}"; }

KEEP=0; YES=0
for a in "$@"; do
  case "$a" in
    --keep-data) KEEP=1 ;;
    --yes|-y)    YES=1 ;;
    -h|--help)   usage 0 ;;
    *) echo "Unknown argument: $a" >&2; usage 1 ;;
  esac
done

if (( KEEP )); then
  docker compose down
  echo "Stopped. Data kept. Restart with: ./scripts/bootstrap.sh"
  exit 0
fi

if (( ! YES )); then
  read -r -p "This deletes ALL GitLab data (volumes) and the root PAT. Type 'yes' to continue: " ans
  [[ "$ans" == "yes" ]] || { echo "Aborted."; exit 1; }
fi
docker compose down -v
rm -rf .state
echo "Removed containers, volumes and .state/. Tokens in .env are now invalid; bootstrap.sh will replace them."
