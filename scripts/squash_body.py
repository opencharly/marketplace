#!/usr/bin/env python3
"""Render and verify a squash body with one parseable Assisted-by trailer."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys


CONFIDENCE_TIERS = (
    "fully tested and validated",
    "analysed on a live system",
    "documentation reviewed",
    "syntax check only",
    "theoretical suggestion",
)
TRAILER = re.compile(
    r"^Assisted-by: "
    r"(?P<identity>[^<>\s]+(?: [^<>\s]+){2,}) "
    r"\((?P<confidence>"
    + "|".join(re.escape(tier) for tier in CONFIDENCE_TIERS)
    + r")\)$"
)


class ContractError(ValueError):
    """The proposed squash message violates the attribution contract."""


def validate_trailer(trailer: str) -> None:
    if not TRAILER.fullmatch(trailer):
        raise ContractError(
            "trailer must be exactly "
            "'Assisted-by: <Harness> <Provider Full Model Name> (<confidence>)' "
            "with a supported confidence tier"
        )


def parsed_trailers(body: bytes) -> bytes:
    try:
        result = subprocess.run(
            ["git", "interpret-trailers", "--parse"],
            input=body,
            check=False,
            capture_output=True,
        )
    except OSError as error:
        raise ContractError(f"cannot run git interpret-trailers: {error}") from error
    if result.returncode != 0:
        detail = result.stderr.decode(errors="replace").strip()
        raise ContractError(f"git interpret-trailers failed: {detail}")
    return result.stdout


def validate_body(body: bytes, trailer: str) -> None:
    validate_trailer(trailer)
    try:
        text = body.decode("utf-8")
    except UnicodeDecodeError as error:
        raise ContractError("squash body must be UTF-8") from error
    if "\0" in text:
        raise ContractError("squash body must not contain NUL")
    if text.count("Assisted-by:") != 1:
        raise ContractError("squash body must contain exactly one Assisted-by trailer")
    if trailer not in text.splitlines():
        raise ContractError("expected Assisted-by trailer is not a standalone line")
    expected = f"{trailer}\n".encode()
    actual = parsed_trailers(body)
    if actual != expected:
        raise ContractError(
            "git interpret-trailers did not parse exactly the expected trailer"
        )


def render_body(prose: str, trailer: str) -> bytes:
    validate_trailer(trailer)
    prose = prose.strip()
    if not prose:
        raise ContractError("squash prose must not be empty")
    if "\0" in prose:
        raise ContractError("squash prose must not contain NUL")
    if "Assisted-by:" in prose:
        raise ContractError("squash prose must not contain an Assisted-by trailer")
    body = f"{prose}\n\n{trailer}".encode()
    validate_body(body, trailer)
    return body


def self_test() -> None:
    trailer = "Assisted-by: Codex OpenAI GPT-5.6 Sol (documentation reviewed)"
    body = render_body("Explain the completed cutover.", trailer)
    assert body == f"Explain the completed cutover.\n\n{trailer}".encode()
    validate_body(body, trailer)

    malformed = (
        f"Explain the completed cutover.  {trailer}".encode(),
        f"Explain the completed cutover.\n{trailer}".encode(),
    )
    for candidate in malformed:
        try:
            validate_body(candidate, trailer)
        except ContractError:
            pass
        else:
            raise AssertionError("accepted a non-parseable trailer placement")

    invalid_trailers = (
        "Assisted-by: Codex (documentation reviewed)",
        "Assisted-by: <Harness> <Provider Full Model Name> (<confidence>)",
        "Assisted-by: Codex OpenAI GPT-5.6 Sol (reviewed)",
    )
    for candidate in invalid_trailers:
        try:
            validate_trailer(candidate)
        except ContractError:
            pass
        else:
            raise AssertionError("accepted a noncanonical attribution trailer")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--trailer", help="expected concrete Assisted-by trailer")
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify the complete message read from standard input",
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="run parser-backed contract tests",
    )
    args = parser.parse_args()

    try:
        if args.self_test:
            self_test()
            print("squash body contract self-test passed")
            return 0
        if not args.trailer:
            parser.error("--trailer is required unless --self-test is used")
        source = sys.stdin.buffer.read()
        if args.check:
            validate_body(source, args.trailer)
        else:
            try:
                prose = source.decode("utf-8")
            except UnicodeDecodeError as error:
                raise ContractError("squash prose must be UTF-8") from error
            sys.stdout.buffer.write(render_body(prose, args.trailer))
    except ContractError as error:
        print(f"squash body contract failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
