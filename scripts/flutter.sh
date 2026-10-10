#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
export PUB_CACHE="$PROJECT_DIR/.tooling/pub-cache"
export XDG_CONFIG_HOME="$PROJECT_DIR/.tooling/config"
export FLUTTER_SUPPRESS_ANALYTICS=true
export CI=true
if [ -x "$PROJECT_DIR/.tooling/flutter/bin/flutter" ]; then
  exec "$PROJECT_DIR/.tooling/flutter/bin/flutter" "$@"
fi
if command -v flutter >/dev/null 2>&1; then
  exec flutter "$@"
fi
echo "Install Flutter and add it to PATH, then run this command again."
exit 1
