#!/usr/bin/env bash
# Run ShellCheck on the JenkinsBuild shell surface (explicit file list).
#
# Exceptions (intentionally not scanned):
#   - util/exp — Tcl/Expect (#!/usr/bin/expect), not a POSIX/Bash shell script
#   - .git and other non-build scripts
#
# Default severity is "error" so CI stays green while legacy warnings remain.
# Stricter:  SHELLCHECK_SEVERITY=warning ./scripts/run-shellcheck.sh

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SEVERITY="${SHELLCHECK_SEVERITY:-error}"

files=(
  build.sh dist.sh
  config/defaultconfig
  config/defaultconfig.local.example
  config/argsparser
  config/jsonconfig
  config/sshfunctions
  config/utilconfig
  config/fcmconfig
  config/buildenvironment
  util/sendteams
  util/sendslack
  util/sendemail
  util/makejson
  util/makehtml
  util/makePath
  util/versions
  util/dist_shlib
  platform/android.sh
  platform/ios.sh
  platform/jb_json_helpers.sh
  plugins/allatori_android.sh
  plugins/ixshield_ios.sh
  plugins/obfuscation_android.sh
  test/obfuscation_android.sh
  test/obfuscation_ios.sh
  test/android/app/check.sh
  scripts/validate-config.sh
)

exec shellcheck -x -S "$SEVERITY" -- "${files[@]}"
