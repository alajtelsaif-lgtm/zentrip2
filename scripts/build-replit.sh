#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ ! -x .local/toolchains/jdk/bin/java ] || [ ! -x .local/toolchains/flutter/bin/flutter ]; then
  bash scripts/setup-toolchains.sh
fi
export JAVA_HOME="$PWD/.local/toolchains/jdk"
export PATH="$JAVA_HOME/bin:$PWD/.local/toolchains/flutter/bin:$PATH"
flutter pub get
flutter build web --release --no-wasm-dry-run
# Test in an isolated environment; never pass the live connection into test contexts.
bash scripts/test-backend.sh
mvn -B -f backend/pom.xml -DskipTests package
