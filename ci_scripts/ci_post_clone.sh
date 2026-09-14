#!/bin/sh
#
# Xcode Cloud runs this automatically right after cloning the repo, before
# any build/archive step. Its one job: give every CI build a genuinely
# unique CFBundleVersion (build number) by writing Xcode Cloud's own,
# always-incrementing $CI_BUILD_NUMBER into the project's
# CURRENT_PROJECT_VERSION — instead of the "1" that's hardcoded in
# project.yml/AI.xcodeproj and never changes on its own.
#
# Without this, every archive ships as the exact same version+build pair
# (1.0 (1)). App Store Connect silently rejects any build after the first
# one that ever got fully processed with that pair — which is exactly the
# generic "Preparing build for App Store Connect failed" error with no
# further detail, the one this script exists to fix.
set -e

if [ -z "$CI_BUILD_NUMBER" ]; then
    echo "ci_post_clone.sh: CI_BUILD_NUMBER not set (not an Xcode Cloud run?) — leaving version numbers alone."
    exit 0
fi

cd "$CI_PRIMARY_REPOSITORY_PATH"
echo "ci_post_clone.sh: setting CURRENT_PROJECT_VERSION to $CI_BUILD_NUMBER"
xcrun agvtool new-version -all "$CI_BUILD_NUMBER"
