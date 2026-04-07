##
# Shared jq helpers for platform/android.sh and platform/ios.sh.
# Requires: jsonConfig, JQ (set by config/jsonconfig before these platform files are sourced).
# Convention: *_bool returns 1 for JSON true and 0 otherwise (matches legacy test … && echo 1 || echo 0).

jb_jq_bool() {
  test "$(cat "$jsonConfig" | $JQ "$1")" = true && echo 1 || echo 0
}

jb_jq_str() {
  cat "$jsonConfig" | $JQ "$1" | tr -d '"'
}
