#!/usr/bin/env bash
# Smokes Android obfuscation screenshot path via plugins/obfuscation_android.sh
# (same implementation as platform/android.sh → makeObfuscationScreenshot).

set -euo pipefail

TOP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TOP_DIR"

export WORKSPACE="$TOP_DIR"
export ANDROID_APP_PATH="test/android/app"
export IS_RELEASE=1
export DEBUGGING=0
export OUTPUT_FOLDER="$TOP_DIR/test/android/output"
export jsonConfig="$TOP_DIR/test/config.json"
export JQ="jq"
export APP_ROOT_PREFIX="$TOP_DIR"
export TOP_PATH="."
export USING_SCP=0
export GIT_USER="test_user"
export GIT_BRANCH="test_branch"
export APK_GOOGLESTORE="test.apk"
export Obfuscation_SCREENSHOT="obfuscation_screenshot.png"
export Obfuscation_INPUT_FILE="images/JenkinsConfigHelp.png"
export Obfuscation_OUTPUT_FILE="obfuscation_output.png"

mkdir -p "$OUTPUT_FOLDER"
mkdir -p "$WORKSPACE/$ANDROID_APP_PATH"
touch "$OUTPUT_FOLDER/$APK_GOOGLESTORE"

cat > "$WORKSPACE/$ANDROID_APP_PATH/check.sh" << 'EOF'
#!/bin/bash
echo "Running obfuscation check..."
echo "Test successful!"
EOF
chmod +x "$WORKSPACE/$ANDROID_APP_PATH/check.sh"

mkdir -p "$(dirname "$WORKSPACE/$Obfuscation_INPUT_FILE")"
if [ ! -f "$WORKSPACE/$Obfuscation_INPUT_FILE" ]; then
    echo "Test file" > "$WORKSPACE/$Obfuscation_INPUT_FILE"
fi

# shellcheck source=../plugins/obfuscation_android.sh
. "${TOP_DIR}/plugins/obfuscation_android.sh"
jb_android_make_obfuscation_screenshot

echo "Test completed."
