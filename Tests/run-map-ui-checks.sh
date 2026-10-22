#!/bin/sh
# Run against a built app on a disposable/test simulator. Requires XcodeGen.
set -eu
cd "$(dirname "$0")/.."
device=${1:?Usage: run-map-ui-checks.sh SIMULATOR_UUID BUILT_APP_PATH}
app_path=${2:?Pass the built simulator .app path}
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/spaces-map-ui.XXXXXX")
cp Tests/MapMovementUITests.swift "$check_dir/"
cat > "$check_dir/project.yml" <<'YAML'
name: MapValidation
options:
  deploymentTarget:
    iOS: "17.0"
settings:
  base:
    SWIFT_VERSION: "5.0"
    CODE_SIGNING_ALLOWED: NO
targets:
  MapMovementUITests:
    type: bundle.ui-testing
    platform: iOS
    sources: [MapMovementUITests.swift]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.husseinalaa.map-movement-validation
        GENERATE_INFOPLIST_FILE: YES
schemes:
  MapMovement:
    build:
      targets:
        MapMovementUITests: all
    test:
      targets: [MapMovementUITests]
YAML
xcodegen generate --spec "$check_dir/project.yml"
xcrun simctl install "$device" "$app_path"
xcodebuild -project "$check_dir/MapValidation.xcodeproj" -scheme MapMovement \
 -destination "platform=iOS Simulator,id=$device" \
 -derivedDataPath "$check_dir/build" -resultBundlePath "$check_dir/results.xcresult" test
