#!/usr/bin/env bash
# Smokes iOS IxShield obfuscation screenshot via plugins/ixshield_ios.sh
# (same path as platform/ios.sh → makeObfuscationScreenshot).

set -euo pipefail

TOP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TOP_DIR" || exit 1

cleanup() {
    rm -f "$TOP_DIR/IxShieldCheck.sh"
}
trap cleanup EXIT

cat > "$TOP_DIR/IxShieldCheck.sh" << 'EOF'
#!/bin/sh
echo "Running obfuscation check..."
echo "Test successful!"
EOF
chmod +x "$TOP_DIR/IxShieldCheck.sh"

export WORKSPACE="$TOP_DIR"
export jsonConfig="$TOP_DIR/test/config.json"
export JQ="jq"
export PROJECT_NAME="test/ios/test"
export OUTPUT_FOLDER="$TOP_DIR/test/ios/output"
mkdir -p "$OUTPUT_FOLDER"
export OUTPUT_FILENAME_APPSTORE_IX_SHIELD_CHECK="IxShieldCheck.png"
export DEBUGGING=0
export systemName="JenkinsBuildTest"
export OBFUSCATION_SOURCE=""

mkdir -p "$WORKSPACE/$PROJECT_NAME/ObjC"
cp -f "$TOP_DIR/test/ios/fixtures/SplashViewController.m" \
    "$WORKSPACE/$PROJECT_NAME/ObjC/SplashViewController.m"

# shellcheck source=../plugins/ixshield_ios.sh
. "${TOP_DIR}/plugins/ixshield_ios.sh"
jb_ixshield_make_obfuscation_screenshot

if [ ! -f "$OUTPUT_FOLDER/$OUTPUT_FILENAME_APPSTORE_IX_SHIELD_CHECK" ]; then
    echo "Expected PNG not created: $OUTPUT_FOLDER/$OUTPUT_FILENAME_APPSTORE_IX_SHIELD_CHECK"
    exit 1
fi
echo "iOS obfuscation screenshot smoke test OK"
