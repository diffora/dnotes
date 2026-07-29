#!/bin/sh
# Runs the test suite.
#
# Works with either toolchain, because which one is active is not a decision this
# script should force:
#
#   * Full Xcode — swift-testing is found the normal way, so `swift test` is enough.
#   * Command Line Tools only — SwiftPM does not add the framework search path (that
#     is Xcode's job), and CLT ships _Testing_Foundation.framework WITHOUT its
#     .swiftmodule, so the Testing+Foundation cross-import overlay cannot be built.
#     Both are worked around below. Do not move these flags into Package.swift as
#     `unsafeFlags`: the build then succeeds and zero tests run, silently.
set -eu

cd "$(dirname "$0")/.."

DEVELOPER_DIR_PATH="$(xcode-select -p)"

if [ -d "$DEVELOPER_DIR_PATH/Platforms/MacOSX.platform" ]; then
    exec swift test "$@"
fi

FRAMEWORKS="$DEVELOPER_DIR_PATH/Library/Developer/Frameworks"
if [ ! -d "$FRAMEWORKS/Testing.framework" ]; then
    echo "Testing.framework not found in $FRAMEWORKS" >&2
    echo "Active developer directory is $DEVELOPER_DIR_PATH — check 'xcode-select -p'." >&2
    exit 1
fi

exec swift test \
    -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
    -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
    -Xlinker -F -Xlinker "$FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
    "$@"
