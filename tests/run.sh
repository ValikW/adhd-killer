#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library -module-cache-path "$test_dir/cache" \
    Sources/FocusCore.swift tests/FocusCoreTests.swift -o "$test_dir/FocusCoreTests"
"$test_dir/FocusCoreTests"
swiftc -parse-as-library -module-cache-path "$test_dir/cache" \
    Sources/FocusCore.swift Sources/FocusUsageStore.swift tests/FocusUsageStoreTests.swift \
    -o "$test_dir/FocusUsageStoreTests"
"$test_dir/FocusUsageStoreTests"
