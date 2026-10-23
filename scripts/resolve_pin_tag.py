#!/usr/bin/env python3
"""resolve_pin_tag.py — pick the tag a @github pin advances to, WITHIN THE PIN'S OWN SCHEME.

WHY THIS EXISTS. Every entry in the refs list is a Go-module version, and two tag schemes live
in this org:

  * the SUPERPROJECT scheme   v<YYYY>.<DDD>.<HHMM>     4 digits, 3 digits, 4 digits
  * the Go-MODULE scheme      v0.<YYYYDDD>.<HHMM>      1 digit,  7 digits, 3-4 digits

A repo can publish BOTH — `spec` and `sdk` do. The resolver this replaces took EVERY `vN.N.N`
tag in the repo, sorted the components NUMERICALLY, and took the last one. The Go-module
scheme's first component is the fixed major `0`, so `0` sorts BELOW the year `2026`: the
resolver moved a Go-module pin to the superproject's newest tag, which is not a valid Go
module version at all, and moved it BACKWARD in time while doing so
(opencharly/marketplace#553 — the refresh PR that carried the corruption).

THE RULE. A pin's SCHEME is a property of the pin the list already carries, not of the repo's
tag list: the shape of the tag the pin holds decides which tags are eligible. A candidate is
eligible iff it has the same number of components AND its first two components have the same
character widths as the pin's. The newest eligible tag wins — and a pin NEVER moves BACKWARD.

The component WIDTHS are the scheme, because the widths are fixed by the scheme while the
values grow: the superproject scheme's first component is a YEAR (4 digits, and it changes),
and the Go-module scheme's is a MAJOR (1 digit, and it does not). The third component is
deliberately NOT part of the key: the Go-module scheme strips the leading zeros of its
`HHMM`, so that component's width varies inside one scheme (`v0.2026296.7` and
`v0.2026296.734` are the same scheme, an hour and a half apart in the same afternoon).

usage:
  resolve_pin_tag.py --old <tag>             # the repo's tags on stdin, one per line
  resolve_pin_tag.py --old <tag> --tags <f>  # the repo's tags from a file

exit 0  stdout: the tag to pin
exit 3  no tag in the pin's scheme            (stderr: why) — the pin stays
exit 4  the newest in the scheme is OLDER     (stderr: why) — the pin stays
exit 2  the pin is not a version tag this resolver can read
"""
import argparse
import re
import sys

# A version tag: `v` and one or more numeric components. Anything else (a branch ref, a
# `latest`, a pre-release) is not a candidate.
VERSION = re.compile(r"^v(\d+(?:\.\d+)*)$")

# The status codes the caller branches on. A pin that stays is not a failure of the run: the
# caller reports it and moves on, because a pin that cannot be advanced safely is a pin that
# a human has to look at.
STAY_NO_TAG_IN_SCHEME = 3
STAY_SCHEME_IS_OLDER = 4
UNREADABLE_PIN = 2


def split_tag(tag):
    """The numeric components of a version tag, or None when it is not one."""
    m = VERSION.match(tag.strip())
    return m.group(1).split(".") if m else None


def scheme_key(parts):
    """The scheme of a tag: its component count and the widths of its first two components."""
    return (len(parts), len(parts[0]), len(parts[1]))


def same_scheme(old_parts, cand_parts):
    """Is this candidate in the SAME scheme as the pin the list already carries?

    The scheme is the pin's, not the repo's: a repo that publishes both schemes is resolved
    in the scheme its pin speaks, so a Go-module pin is never handed a superproject tag.
    """
    if len(cand_parts) < 3 or len(old_parts) < 3:
        return False
    return scheme_key(cand_parts) == scheme_key(old_parts)


def compare(left, right):
    """-1 / 0 / +1 — the two tags compared NUMERICALLY, component by component."""
    for l, r in zip(left, right):
        li, ri = int(l), int(r)
        if li != ri:
            return -1 if li < ri else 1
    return 0


def resolve(old, tags):
    """The tag this pin should carry, the reason when it should not move, and the status.

    `tag` is None when the pin stays; `reason` says why; `status` is one of the STAY_* /
    UNREADABLE_PIN codes above, or 0 when the pin moves.
    """
    old_parts = split_tag(old)
    if old_parts is None or len(old_parts) < 3:
        return None, f"{old} is not a version tag this resolver can read", UNREADABLE_PIN
    key = scheme_key(old_parts)
    best_parts, best_tag = None, None
    for raw in tags:
        cand = split_tag(raw)
        if cand is None:
            continue
        if not same_scheme(old_parts, cand):
            continue
        if best_parts is None or compare(cand, best_parts) > 0:
            best_parts, best_tag = cand, raw.strip()
    if best_tag is None:
        return None, (
            f"no tag in the scheme of {old} "
            f"({key[0]} components, first {key[1]} digit(s), second {key[2]} digit(s))"
        ), STAY_NO_TAG_IN_SCHEME
    if compare(best_parts, old_parts) < 0:
        return None, (
            f"the newest tag in that scheme is {best_tag}, which is OLDER than {old}"
        ), STAY_SCHEME_IS_OLDER
    return best_tag, "", 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--old", required=True, help="the tag the pin currently carries")
    ap.add_argument("--tags", help="a file of the repo's tags, one per line (default: stdin)")
    a = ap.parse_args(argv)
    if a.tags:
        with open(a.tags, encoding="utf-8") as fh:
            tags = fh.read().splitlines()
    else:
        tags = sys.stdin.read().splitlines()
    tag, reason, status = resolve(a.old, tags)
    if tag is None:
        print(reason, file=sys.stderr)
        return status
    print(tag)
    return 0


if __name__ == "__main__":
    sys.exit(main())
