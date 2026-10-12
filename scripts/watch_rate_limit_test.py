#!/usr/bin/env python3
"""Check the pure protocol predicate; no GitHub executable or service is simulated."""

import argparse
import re
import subprocess
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
HELPER = HERE / "_watch_common.sh"


class Predicate(unittest.TestCase):
    def classify(self, payload, command_exit):
        result = subprocess.run(
            ["bash", "-c", 'source "$1"; watch_is_rate_limited "$2" "$3"',
             "predicate", str(HELPER), payload, str(command_exit)],
            capture_output=True, text=True,
        )
        self.assertIn(result.returncode, (0, 1), result.stderr)
        return result.returncode

    def test_recorded_graphql_quota_envelope(self):
        history = (HERE.parent / "CHANGELOG/2026.272.0920.md").read_text()
        match = re.search(r"watch_is_rate_limited '(\{[^\n]+\})'", history)
        self.assertIsNotNone(match, "canonical quota example must remain available")
        self.assertEqual(self.classify(match.group(1), 0), 0)

    def test_failed_http_throttle_diagnostic(self):
        self.assertEqual(self.classify("gh: HTTP 429: Too Many Requests", 1), 0)

    def test_failed_api_quota_diagnostic(self):
        self.assertEqual(self.classify("gh: API rate limit exceeded", 1), 0)

    def test_successful_text_is_not_a_command_failure(self):
        self.assertEqual(self.classify("HTTP 429", 0), 1)

    def test_typed_non_quota_error_overrides_message_words(self):
        payload = '{"errors":[{"type":"NOT_FOUND","message":"rate limit repository"}]}'
        self.assertEqual(self.classify(payload, 1), 1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--helper", type=Path, default=HELPER,
                        help="actual historical helper for regression comparison")
    args, remaining = parser.parse_known_args()
    HELPER = args.helper.resolve()
    unittest.main(argv=[__file__, *remaining], verbosity=2)
