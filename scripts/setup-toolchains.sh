#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tools="$PWD/.local/toolchains"
mkdir -p "$tools"
if [ ! -x "$tools/jdk/bin/java" ]; then
  curl --fail --location --retry 3 \
    'https://api.adoptium.net/v3/binary/latest/25/ga/linux/x64/jdk/hotspot/normal/eclipse' \
    -o "$tools/jdk.tar.gz"
  mkdir -p "$tools/jdk"
  tar -xzf "$tools/jdk.tar.gz" -C "$tools/jdk" --strip-components=1
  rm "$tools/jdk.tar.gz"
fi
if [ ! -d "$tools/flutter" ]; then
  git clone --depth 1 --branch 3.44.0 https://github.com/flutter/flutter.git "$tools/flutter"
fi
if [ "$(git -C "$tools/flutter" describe --tags --exact-match 2>/dev/null)" != "3.44.0" ]; then
  git -C "$tools/flutter" fetch --depth 1 origin tag 3.44.0
  git -C "$tools/flutter" checkout --detach 3.44.0
fi
"$tools/flutter/bin/flutter" --disable-analytics
"$tools/flutter/bin/flutter" precache --web
