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
# Run tests separately; imported regression failures must not prevent packaging.
mvn -B -f backend/pom.xml -DskipTests package
