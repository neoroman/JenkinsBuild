#!/usr/bin/env python3
"""Validate a config.json against schema/public-config.schema.json."""
from __future__ import annotations

import json
import sys
from pathlib import Path


def main() -> None:
    if len(sys.argv) != 3:
        sys.stderr.write("usage: validate_config.py <schema.json> <config.json>\n")
        sys.exit(2)
    schema_path = Path(sys.argv[1])
    config_path = Path(sys.argv[2])
    if not schema_path.is_file():
        sys.stderr.write(f"Schema not found: {schema_path}\n")
        sys.exit(2)
    if not config_path.is_file():
        sys.stderr.write(f"Config not found: {config_path}\n")
        sys.exit(2)
    try:
        import jsonschema
    except ImportError:
        sys.stderr.write("Missing dependency: pip install jsonschema\n")
        sys.exit(3)
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    instance = json.loads(config_path.read_text(encoding="utf-8"))
    try:
        jsonschema.validate(instance=instance, schema=schema)
    except jsonschema.ValidationError as e:
        sys.stderr.write(f"{list(e.absolute_path) or '<root>'}: {e.message}\n")
        sys.exit(1)
    print(f"OK: {config_path} validates against {schema_path.name}")


if __name__ == "__main__":
    main()
