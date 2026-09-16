#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/spaces-message-checks.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
xcrun swiftc -parse-as-library -module-cache-path "$check_dir/modules" \
  "$project_root/Sources/AI/Auth/SpacechatService.swift" \
  "$project_root/Sources/AI/Models/CustomDot.swift" \
  "$project_root/Tests/SpacesMessagingChecks.swift" -o "$check_dir/checks"
"$check_dir/checks" "$check_dir/data"
