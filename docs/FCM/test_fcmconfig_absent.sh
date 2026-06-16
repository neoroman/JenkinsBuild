#!/bin/bash
set -euo pipefail

# Locate repository root relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="/Users/henry/tc/JenkinsBuild"

# Temporary workspace and files
TEST_DIR="${SCRIPT_DIR}/test_run_absent"
rm -rf "${TEST_DIR}"
mkdir -p "${TEST_DIR}/src_dir" "${TEST_DIR}/workspace"

# Setup dummy source files (just in case)
echo "dummy release src" > "${TEST_DIR}/src_dir/google-services-release.json"
echo "dummy debug src" > "${TEST_DIR}/src_dir/google-services-debug.json"

export JQ="$(command -v jq)"
export WORKSPACE="${TEST_DIR}/workspace"
export INPUT_OS="android"
export IS_RELEASE="0"
export APP_ROOT_PREFIX="/"
export TOP_PATH="/"

# Test Case 1: ini_src and ini_dst are COMPLETELY ABSENT
echo "=== Test Case 1: ini_src and ini_dst are absent ==="
cat <<EOF > "${TEST_DIR}/config.json"
{
  "android": {
    "LiveServer": {
      "FCM": {
        "release_src": "${TEST_DIR}/src_dir/google-services-release.json",
        "release_dst": "${TEST_DIR}/workspace/app/google-services.json",
        "debug_src": "${TEST_DIR}/src_dir/google-services-debug.json",
        "debug_dst": "${TEST_DIR}/workspace/app/google-services-debug.json"
      }
    }
  }
}
EOF
export jsonConfig="${TEST_DIR}/config.json"

# Source fcmconfig and expect it to complete successfully (no error, exits with 0)
. "${REPO_ROOT}/config/fcmconfig"
echo "Completed sourcing fcmconfig. Checking output directory..."
if [ -f "${TEST_DIR}/workspace/app/google-services-ini.json" ]; then
  echo "Error: ini file should not have been copied!"
  exit 1
fi
echo "Test Case 1 Passed! Sourcing succeeded without errors."

# Test Case 2: ini_src and ini_dst are empty strings
echo "=== Test Case 2: ini_src and ini_dst are empty strings ==="
rm -rf "${TEST_DIR}/workspace/app"
cat <<EOF > "${TEST_DIR}/config.json"
{
  "android": {
    "LiveServer": {
      "FCM": {
        "release_src": "${TEST_DIR}/src_dir/google-services-release.json",
        "release_dst": "${TEST_DIR}/workspace/app/google-services.json",
        "debug_src": "${TEST_DIR}/src_dir/google-services-debug.json",
        "debug_dst": "${TEST_DIR}/workspace/app/google-services-debug.json",
        "ini_src": "",
        "ini_dst": ""
      }
    }
  }
}
EOF
. "${REPO_ROOT}/config/fcmconfig"
echo "Test Case 2 Passed! Sourcing succeeded without errors."

# Test Case 3: ini_src and ini_dst are null / non-string
echo "=== Test Case 3: ini_src and ini_dst are null ==="
rm -rf "${TEST_DIR}/workspace/app"
cat <<EOF > "${TEST_DIR}/config.json"
{
  "android": {
    "LiveServer": {
      "FCM": {
        "release_src": "${TEST_DIR}/src_dir/google-services-release.json",
        "release_dst": "${TEST_DIR}/workspace/app/google-services.json",
        "debug_src": "${TEST_DIR}/src_dir/google-services-debug.json",
        "debug_dst": "${TEST_DIR}/workspace/app/google-services-debug.json",
        "ini_src": null,
        "ini_dst": null
      }
    }
  }
}
EOF
. "${REPO_ROOT}/config/fcmconfig"
echo "Test Case 3 Passed! Sourcing succeeded without errors."

echo "All verification tests passed!"
