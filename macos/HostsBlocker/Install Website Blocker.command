#!/bin/bash
set -euo pipefail
STINT_SETUP_DIR="$(cd "$(dirname "$0")" && pwd)"
printf '%s\n' 'Stint website blocker setup' '' 'This installs or upgrades the helper that selects Stint’s local web proxy during focus.' 'Browsers using macOS proxy settings are protected. HTTPS stays encrypted. No Apple subscription is needed.' 'Previous HTTP/HTTPS proxy settings are restored when focus stops, the app closes or its 30-second heartbeat expires. Existing proxies are not overwritten.' 'One Mac account can use the helper. Remove Website Blocker.command uninstalls it.' ''
read -r -p 'Install for your account? Type yes: ' STINT_SETUP_REPLY
if [ "$STINT_SETUP_REPLY" != yes ]; then exit 0; fi
/usr/bin/sudo "$STINT_SETUP_DIR/StintHostsHelper" install
read -r -p 'Press Return to close this setup session. ' STINT_SETUP_REPLY
