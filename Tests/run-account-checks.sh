#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/spaces-account-checks.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "$check_dir/modules" \
 "$project_root/Sources/AI/Auth/SpacechatAuth.swift" \
 "$project_root/Sources/AI/Auth/SpacechatWords.swift" \
 "$project_root/Sources/AI/Auth/AuthState.swift" \
 "$project_root/Sources/AI/Auth/SpacechatSync.swift" \
 "$project_root/Sources/AI/Persistence/SaveManager.swift" \
 "$project_root/Tests/SharedAccountChecks.swift" -o "$check_dir/checks"
"$check_dir/checks"
