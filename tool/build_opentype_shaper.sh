#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/native
"${CXX:-c++}" -std=c++17 -O1 -fPIC -shared -pthread \
  -Ithird_party/harfbuzz/src third_party/harfbuzz/src/harfbuzz.cc native/opentype_bridge.cc \
  -o build/native/libwriting_harfbuzz.so
