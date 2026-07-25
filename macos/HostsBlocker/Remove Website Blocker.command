#!/bin/bash
set -euo pipefail
STINT_SETUP_DIR="$(cd "$(dirname "$0")" && pwd)"
printf '%s\n' 'This stops and removes Stint’s website helper and restores its proxy settings.' 'Your saved app/domain list and unrelated network settings are kept.' ''
read -r -p 'Remove it? Type yes: ' STINT_SETUP_REPLY
if [ "$STINT_SETUP_REPLY" != yes ]; then exit 0; fi
/usr/bin/sudo "$STINT_SETUP_DIR/StintHostsHelper" uninstall
read -r -p 'Press Return to close this setup session. ' STINT_SETUP_REPLY
