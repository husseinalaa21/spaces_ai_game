# Dmap movement validation

The main Dmap, team collection map, and project universe now share `DotMapViewport` camera math. Dragging uses screen-point deltas in a fixed viewport coordinate space. Release keeps the final position; it does not apply a predicted translation that pulls the team map backward. Interrupted and cancelled gestures clear or rebase their translation before movement resumes.

On iOS 17 and later, pinch zoom keeps the world point beneath the initial pinch anchor in place, including when zoom reaches its limits. iOS 16 retains center-anchored zoom through its older SwiftUI gesture API. Zoom controls preserve the world point at screen center. Grid spacing follows camera scale and coarsens at distant zooms to bound drawing work.

Main/team map drags take priority over button taps so a moving dot cannot open its screen on release. Project navigation keeps the separate long-press dot-placement gesture and suspends camera movement while a dot is held. Camera movement and reset controls update directly to avoid interrupting an in-flight camera animation at its stored destination.

## Repeatable checks

Run `Tests/run-map-checks.sh` for 66 checks of drag distance/direction at five zoom levels, release stability, cancellation, pinch focal-point invariance, clamping, pinch/drag transitions, zoom controls, recentering, and camera suspension during individual dot placement.

Build the app with:

```sh
xcodebuild -project AI.xcodeproj -scheme AI -configuration Debug \
 -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
 -derivedDataPath /tmp/spacesgameai-native-validation CODE_SIGNING_ALLOWED=NO build
```

Run the UI checks on a test simulator, using its UUID and the built simulator app path:

```sh
Tests/run-map-ui-checks.sh SIMULATOR_UUID \
 '/tmp/spacesgameai-native-validation/Build/Products/Debug-iphonesimulator/Space - Dots & AI.app'
```

The UI runner requires XcodeGen, creates a separate temporary test project, and uses the normal guest entry option if signed out. Use a test simulator because it can enter the local guest workspace. It verifies dragging a button without opening its screen, full-distance pans and release stability, zoom/recenter, pinch then pan, normal team-button taps, and team-map release distance. The project world's individual dot placement is covered by camera suspension checks; its complete connection/delete flow is not exercised by this UI test.

## Local results — 2026-10-22

- Camera checks: 66 passed.
- Simulator build: passed.
- Simulator UI regression: passed on iPhone 17 Pro Max / iOS 27.0 (one scenario, zero failures). Full main-map pan/zoom/recenter and button-drag checks passed; the team map moved the complete 65 × 35 screen points and stayed at that position after release.
- XCTest result bundle: `/tmp/spacesgameai-map-ui-reviewed.xcresult`.
- Simulator preview: `validation/dmap-movement.png`.
