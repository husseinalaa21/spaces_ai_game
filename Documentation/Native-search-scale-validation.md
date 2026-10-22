# Native Space - Dots & AI: research, scale and validation

Target: `Documents/spacesaigame`, Xcode scheme `AI`, bundle `com.husseinalaa.ai`, display name **Space - Dots & AI**. These changes are in the native app. The separate Spacechat website Workspace implementation is not the native file/task runtime.

## Research performed first

The current source has local workspaces, folder-based projects, agent teams, bounded parallel Dot copies and a native action runner using `POST /api/spaces/agents`. The root README's original Phase 1–2 description is historical and does not describe all of today's source.

The native runner previously scanned the first folder listing for case-insensitive line substrings on the main actor. Its parser accepted an unbounded action list without independently validating the server contract. File-change approvals could remain open while another editor changed the target; the original approved draft would then overwrite the newer file. The existing messaging test script also failed to compile because its collaborators no longer matched current app code.

Primary research informing the implementation:

- [Anthropic contextual retrieval](https://www.anthropic.com/research/contextual-retrieval): retain document context around retrieved passages and evaluate retrieval strategies. This update preserves source filenames, overlapping line windows and revision hashes, with BM25/phrase ranking. It does not claim to implement semantic embeddings.
- [Anthropic agent evaluation](https://www.anthropic.com/research/demystifying-evals-for-ai-agents): evaluate tool execution and resulting state, rather than treating a fluent answer as evidence of success. The native checks use actual temporary files, the runner and approvals, with intercepted model replies.
- [Apple concurrency support](https://developer.apple.com/documentation/swiftdata/concurrencysupport): isolate stateful work from UI access. This app uses files rather than SwiftData, so a regular Swift actor holds the derived retrieval cache; no database migration was introduced.
- [Apple background tasks](https://developer.apple.com/documentation/backgroundtasks): background execution is system-controlled. This update does not claim that native agent work can run continuously after iOS suspends or terminates the app.

## Implemented behavior

### Local retrieval

`WorkspaceResearch` performs file I/O, chunk indexing and ranking in an actor. It indexes only the selected shared folder's UTF-8 text, skips hidden/generated directories and symbolic links, and retains at most one folder's cache. Unchanged file metadata reuses parsed passages. Results carry relative path, line range, SHA-256 source revision and text; the main-actor runner rechecks the actual current source hash before delivering evidence to a model.

Ranking combines BM25 term scores, exact-phrase matches and filename matches. Long single-line files are split into bounded segments. Repeated contained excerpts are suppressed and results include at most three passages per file, up to twelve total. There are no embedding downloads, external indexing services or new search-provider credentials.

Limits: 2,000 files, 16 MB per indexed folder, 400 KB per text file and 12,000 chunks. Reaching an index limit is explicitly reported. Binary or oversized files are not indexed. The folder inventory cap rises from 400 to 2,000 entries; relevant source names are prioritized in the existing server's 120-file inventory window. The runner sends up to three 6,000-character observations and four 5,000-character tool results, matching the server's existing consumption limits.

This is local document retrieval; it does not add an independent web-research provider to native Dot actions. General Spacechat AI's existing web behavior remains a separate server capability. No claim is made that a model always uses citations correctly.

### Native action validation

`AgentResponseValidation` independently checks the response before any action executes: at most four actions, known types, bounded strings and payloads, relative paths, integral forward line ranges, current task capabilities, and at most ten copy jobs. A copy cannot spawn further copies. A turn waiting on reads/search/code/copies cannot report completion. Malformed turns are rejected as a whole.

The runner also rechecks current catalogue permissions before tools and again after approval waits. `canEdit` is now enforced locally, rather than relying on the server's filtering. Existing file changes require an observed current source revision. Full-file writes and exact replacements compare the approved original content at the moment they commit; new-file creation also verifies that no file appeared during the approval wait. Deletes protect their pre-approval contents. Paths are checked against resolved locations to prevent symbolic-link escape. Undo records remain supported.

Approval waits respond to Swift task cancellation, removing the pending request. Agent calls use a 55-second timeout instead of 150 seconds. This is per-call timeout handling, not a durable native background-worker service.

### Test harness

`Tests/run-agent-checks.sh` compiles the real research engine, response validator, folder store, approvals, JavaScript sandbox and agent runner. Only the surrounding catalogue and model transport are fixtures. It tests retrieval, source freshness, selected-folder isolation, long lines, limits, symbolic links, malformed actions, read-only access, copies, actual runner evidence handoff, file conflicts across approvals, cancellation automatic approval dismissal on cancellation, access revocation during approval, forged writes against read-only workspaces and a 1,000-file corpus.

`Tests/run-messaging-checks.sh` retains its 31 existing messaging/creation checks. Its test-only auth renewal and game-agent collaborator definitions now match the current service; unexpected game-agent/network activity fails the fixture. No real account, message or model request is used by either check suite.

## Verification

- 28 native agent/research/validation checks passed.
- 31 messaging/creation checks passed.
- A 1,000-file, 2,000-passage synthetic corpus retrieved the expected final file beyond the old first-400 boundary; cold search measured about 249 ms on the final run on this Mac. This is a local regression benchmark, not a production AI-quality or device-performance guarantee.
- Full Debug iOS Simulator build succeeded for scheme `AI`, including the new files in the committed Xcode project.
- Installed and launched `com.husseinalaa.ai` on an isolated iPhone 17 Pro Max / iOS 27.0 simulator. Confirmed the app stayed running and inspected the sign-in screen. This smoke check did not sign in or exercise a live model.

Build command:

```sh
xcodebuild -project AI.xcodeproj -scheme AI -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/spacesgameai-native-validation CODE_SIGNING_ALLOWED=NO build
```

Remaining validation: signed device/TestFlight testing, live model output quality and paid-provider behavior. No App Store upload, production deployment, sign-in, or purchase was performed. Existing icon and screenshot changes belonging to the owner were preserved. The requested four-uniformed-Dot logo is queued in `Documentation/TODO.md`.
