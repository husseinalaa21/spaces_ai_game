# Messages, AI creations, and cosmetic previews

## Spacechat source contracts

Behavior was read from the adjacent Spacechat repository:

- `client/src/pages/MessagesPage.jsx`: filters, local archives, QR payload (`spacechat:user:<username>`), profile links, discovery and group entry points.
- `client/src/context/AppContext.jsx`: message send payload and stable client IDs.
- `ios/App/App/Features/Messages/MessagesView.swift` and its directory/conversation view models: search, archive, saved conversation merging, requests, groups, sharing.
- `ios/App/App/Features/Chat/ViewModels/ChatConversationViewModel.swift`: merge delivered events with saved history; do not treat delivery acknowledgements as incoming messages.
- `ios/App/App/Services/Networking/SpacechatAPI.swift`, `mind/brain/profile.js`, `client.js`, `messaging.js`, and `groups-{admin,public}.js`: endpoints and server response behavior.

All requests use JSON and the existing Keychain `x-spacechat-session` token. HTTP failures, `ok:false`, malformed responses, and expired sessions are surfaced. No test sends a real message or creates a real room.

| Endpoint (POST) | Request | Response used |
| --- | --- | --- |
| `/api/session/bootstrap` | `{}` | `id`, `blockedUsers`, `prepaidDatabase.conversations/messages/requests` |
| `/api/user-directory` | `limit:100` | `users` |
| `/api/user-db` | `id`, `username` | `found`, `blocked`, peer profile, `messages`, `pendingMessages` |
| `/api/poll` | optional `activeChat:{id,username}` | `events`, `activeChatProfile` |
| `/api/send-message` | `id`, `to`, `username`, `text`, `message`, stable `clientMessageId`, `timestamp` | `ok`, `delivered`, `held`, `reason` |
| `/api/typing` | `id`, `username`, `c`, `typing` | `ok` |
| `/api/group/list` | `{}` | `groups` |
| `/api/group/get` | `groupId`, `includeMessages:true` | `group`, `messages`, `joined` |
| `/api/group/create` | `name`, `description`, `visibility`, member IDs, `allowMemberInvite:false`, `background:auto` | created `group` |
| `/api/group/send` | `groupId`, `message`, stable `clientMessageId`, `timestamp` | `ok`, `message`, `group` |
| `/api/group/allow` | `groupId`, `userId` | `ok`; server enforces ownership |
| `/api/guide/message` | `message`, `clientMessageId` | `reply` |

## Storage and lifecycle

A single inbox store belongs to the game hub. It polls only in the foreground and remains alive when switching tabs. History, drafts, read state, archive, mute, and deletion markers are saved atomically in an account-scoped Application Support file. Accounts never share this file. Failed sends retain their original IDs for explicit retry. Repeated pending arrays and live deliveries are deduplicated. A stopped in-flight send becomes retryable after relaunch. Muting suppresses incoming in-app haptics.

The server's `user-db` lookup drains pending messages and is **not** a history endpoint. History saved only in another app's local database is not available to this game. Prepaid history is imported through bootstrap; local archive/read/mute settings remain on this device, matching Spacechat's local-mode model. The game never overwrites Spacechat's entire account database to synchronize those settings.

## AI creations

Chat, Create dot, and Create universe modes use the existing Spacechat AI endpoint. Creation replies are parsed as bounded JSON: allowlisted symbols, finite RGB components, capped stickers, and bounded geometry. A preview must be saved/equipped before changing gameplay. Dots and universes are retained in the player's existing Codable profile, with backward-compatible defaults. Universe creation changes colors/grid/starfield, not game rules. Generated universes render in both practice and final rounds when equipped; choosing a catalog universe clears the override.

## Verification

- `Tests/run-messaging-checks.sh`: 31 deterministic checks with intercepted requests, no live network.
- All application Swift sources type-checked together against the installed iOS simulator SDK and cached Vortex module.
- Full Xcode build/simulator launch attempted but blocked by this environment's nested SwiftPM sandbox and CoreSimulator service access. No device screenshots or live two-account messaging validation were obtained.
- Camera scanning, share sheets, keyboard behavior, purchases, AI endpoint output, and live message/group delivery still need an on-device smoke test.

This change implements the requested messaging and creation flows. It does not port Spacechat voice/video calls, payment messages, attachment upload, or its full assistant directory into the game.
