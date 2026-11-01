#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ ! -x .local/toolchains/jdk/bin/java ]; then
  bash scripts/setup-toolchains.sh
fi

artifact_is_stale() {
  local artifact="$1"
  shift
  for source in "$@"; do
    [ -e "$source" ] || continue
    if find "$source" -type f -newer "$artifact" -print -quit | grep -q .; then
      return 0
    fi
  done
  return 1
}

web_artifact="build/web/index.html"
backend_artifact="backend/target/zentrip-api-1.0.0.jar"
needs_build=false

if [ ! -f "$web_artifact" ] || [ ! -f "$backend_artifact" ]; then
  needs_build=true
elif artifact_is_stale "$web_artifact" \
    lib assets web pubspec.yaml pubspec.lock l10n.yaml scripts/build-replit.sh; then
  needs_build=true
elif artifact_is_stale "$backend_artifact" \
    backend/src backend/pom.xml scripts/build-replit.sh; then
  needs_build=true
fi

if [ "$needs_build" = true ]; then
  bash scripts/build-replit.sh
fi
exec python3 scripts/run-replit.py
