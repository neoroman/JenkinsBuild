#!/usr/bin/env python3
"""Run jb_vercomp.sh through bash and assert legacy comparison contract."""
from __future__ import annotations

import os
import subprocess
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VERCOMP_SH = os.path.join(ROOT, "scripts", "pure", "jb_vercomp.sh")


def _vercomp(left: str, right: str) -> int:
    cmd = [
        "bash",
        "-c",
        'source "$1" && vercomp "$2" "$3"',
        "_",
        VERCOMP_SH,
        left,
        right,
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        raise AssertionError(
            f"vercomp failed ({proc.returncode}): stderr={proc.stderr!r} stdout={proc.stdout!r}"
        )
    return int(proc.stdout.strip())


class VercompPureTests(unittest.TestCase):
    def test_equal_and_padding(self) -> None:
        self.assertEqual(_vercomp("1.0.0", "1.0.0"), 0)
        self.assertEqual(_vercomp("1.0", "1.0.0"), 0)
        self.assertEqual(_vercomp("1.0.0", "1.0"), 0)

    def test_greater_less(self) -> None:
        self.assertEqual(_vercomp("2.0.0", "1.9.9"), 1)
        self.assertEqual(_vercomp("1.9.9", "2.0.0"), 2)
        self.assertEqual(_vercomp("1.2", "1.10"), 2)
        self.assertEqual(_vercomp("1.10", "1.2"), 1)

    def test_single_segment(self) -> None:
        self.assertEqual(_vercomp("10", "9"), 1)
        self.assertEqual(_vercomp("2", "10"), 2)


if __name__ == "__main__":
    unittest.main()
