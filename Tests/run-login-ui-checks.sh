#!/bin/sh
# Run against a built app on a disposable/test simulator. Requires XcodeGen.
set -eu
cd "$(dirname "$0")/.."
device=${1:?Usage: run-login-ui-checks.sh SIMULATOR_UUID BUILT_APP_PATH}
app_path=${2:?Pass the built simulator .app path}
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/spaces-login-ui.XXXXXX")
cp Tests/LoginAppearanceUITests.swift "$check_dir/"
cat > "$check_dir/project.yml" <<'YAML'
name: LoginValidation
options:
  deploymentTarget:
    iOS: "17.0"
settings:
  base:
    SWIFT_VERSION: "5.0"
    CODE_SIGNING_ALLOWED: NO
targets:
  LoginAppearanceUITests:
    type: bundle.ui-testing
    platform: iOS
    sources: [LoginAppearanceUITests.swift]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.husseinalaa.login-appearance-validation
        GENERATE_INFOPLIST_FILE: YES
schemes:
  LoginAppearance:
    build:
      targets:
        LoginAppearanceUITests: all
    test:
      targets: [LoginAppearanceUITests]
YAML
xcodegen generate --spec "$check_dir/project.yml"
xcrun simctl install "$device" "$app_path"
xcodebuild -project "$check_dir/LoginValidation.xcodeproj" -scheme LoginAppearance \
 -destination "platform=iOS Simulator,id=$device" \
 -derivedDataPath "$check_dir/build" -resultBundlePath "$check_dir/results.xcresult" test
