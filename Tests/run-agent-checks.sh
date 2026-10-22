#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/spaces-agent-checks.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "$check_dir/modules" \
 "$project_root/Sources/AI/Engine/WorkspaceResearch.swift" \
 "$project_root/Sources/AI/Engine/AgentResponseValidation.swift" \
 "$project_root/Sources/AI/Views/FolderStore.swift" \
 "$project_root/Sources/AI/Views/AgentAccess.swift" \
 "$project_root/Sources/AI/Views/AgentRunner.swift" \
 "$project_root/Tests/SpacesAgentChecks.swift" -o "$check_dir/checks"
"$check_dir/checks" "$check_dir/data"
