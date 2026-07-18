#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

rsync -avz --delete \
  -e "ssh -i ~/.ssh/maniagroup_deploy" \
  "$SCRIPT_DIR/" \
  root@173.242.49.73:/opt/poruch-static/ \
  --exclude="*.md" \
  --exclude="deploy.sh" \
  --exclude=".git"

echo "✓ poruch.munister.com.ua updated"
