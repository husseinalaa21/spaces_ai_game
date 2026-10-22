#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
binary=$(mktemp -t dot-map-checks)
trap 'rm -f "$binary"' EXIT
xcrun swiftc -swift-version 5 Sources/AI/Engine/DotMapViewport.swift Tests/DotMapChecks.swift -o "$binary"
"$binary"
