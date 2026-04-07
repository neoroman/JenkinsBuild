#!/usr/bin/env bash
# Validate a JenkinsBuild-style config.json against schema/public-config.schema.json.
# Requires: Python 3, pip package jsonschema (`pip install jsonschema`).
#
# Usage:
#   ./scripts/validate-config.sh [PATH_TO_config.json]
# Default PATH is <repo>/test/config.json.
#
# Override schema path:
#   PUBLIC_CONFIG_SCHEMA=/path/to/schema.json ./scripts/validate-config.sh /path/to/config.json

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMA="${PUBLIC_CONFIG_SCHEMA:-$ROOT/schema/public-config.schema.json}"
CONFIG="${1:-$ROOT/test/config.json}"
if [[ ! -f "$SCHEMA" ]]; then
  echo "Schema not found: $SCHEMA" >&2
  exit 2
fi
if [[ ! -f "$CONFIG" ]]; then
  echo "Config not found: $CONFIG" >&2
  exit 2
fi
exec python3 "$ROOT/scripts/validate_config.py" "$SCHEMA" "$CONFIG"
