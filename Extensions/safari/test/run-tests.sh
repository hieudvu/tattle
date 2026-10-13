#!/bin/zsh
# Standalone tests for the pure relay logic (no Safari, no Tattle app). Not part of `swift test`.
set -euo pipefail
here=${0:A:h}
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
swiftc -swift-version 6 -warnings-as-errors -o "$out/relay-tests" \
  "$here/../App/SafariRelay.swift" "$here/../App/UnixSocketLink.swift" "$here/main.swift"
"$out/relay-tests"
