#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/lumine-gpu-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
sources=()
for source in Lumine/*.swift; do
  if [[ "$source" != "Lumine/LumineApp.swift" ]]; then sources+=("$source"); fi
done
swiftc -swift-version 5 -parse-as-library -framework AppKit -framework SwiftUI -framework IOKit \
  -framework CoreWLAN -framework ServiceManagement "${sources[@]}" Tests/SystemMetricsTests.swift -o "$test_dir/SystemTests"
"$test_dir/SystemTests"
