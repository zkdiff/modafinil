#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:---verify}"
case "$MODE" in
  run|--verify) ;;
  *) echo "Usage: $0 [run|--verify]" >&2; exit 2 ;;
esac
cd "$ROOT_DIR"
# Use the same signed bundle builder as release packaging.
./build/build-vigil.sh
sudo -v
BACKUP_DIR="$ROOT_DIR/dist/installed-backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
ditto /Applications/Vigil.app "$BACKUP_DIR/Vigil.app"
pkill -x Vigil || true
ditto "$ROOT_DIR/dist/Vigil.app" /Applications/Vigil.app
codesign --verify --deep --strict /Applications/Vigil.app
sudo launchctl kickstart -k system/com.narcotic.vigil.daemon
open /Applications/Vigil.app
if [ "$MODE" = --verify ]; then
  sleep 2
  pgrep -x Vigil
  launchctl print system/com.narcotic.vigil.daemon | rg 'state = running'
fi
echo "Installed Vigil; previous bundle: $BACKUP_DIR/Vigil.app"
