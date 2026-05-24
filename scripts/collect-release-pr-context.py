#!/usr/bin/env python3
"""Collect merged PR titles and bodies for commits since the previous release tag."""

from __future__ import annotations

import json
import re
import subprocess
import sys

MAX_BODY_CHARS = 2500
PR_LIST_LIMIT = 200


def run(cmd: list[str]) -> str:
    return subprocess.check_output(cmd, text=True).strip()


def commits_in_range(prev_tag: str | None) -> set[str]:
    try:
        if prev_tag:
            output = run(["git", "rev-list", f"{prev_tag}..HEAD"])
        else:
            output = run(["git", "rev-list", "HEAD"])
    except subprocess.CalledProcessError:
        return set()
    return {commit for commit in output.split() if commit}


def commit_subjects(prev_tag: str | None) -> str:
    if prev_tag:
        return run(["git", "log", f"{prev_tag}..HEAD", "--pretty=format:%s"])
    return run(["git", "log", "--pretty=format:%s"])


def list_merged_prs() -> list[dict]:
    output = run(
        [
            "gh",
            "pr",
            "list",
            "--state",
            "merged",
            "--limit",
            str(PR_LIST_LIMIT),
            "--json",
            "number,title,body,mergeCommit",
        ]
    )
    return json.loads(output)


def view_pr(number: str) -> dict | None:
    try:
        output = run(
            [
                "gh",
                "pr",
                "view",
                number,
                "--json",
                "number,title,body,mergeCommit",
            ]
        )
        return json.loads(output)
    except subprocess.CalledProcessError:
        return None


def pr_numbers_from_commit_subjects(subjects: str) -> list[int]:
    numbers: list[int] = []
    seen: set[int] = set()
    for match in re.finditer(r"\(#(\d+)\)", subjects):
        number = int(match.group(1))
        if number not in seen:
            seen.add(number)
            numbers.append(number)
    return numbers


def truncate_body(body: str) -> str:
    body = body.strip()
    if len(body) <= MAX_BODY_CHARS:
        return body
    return body[:MAX_BODY_CHARS].rstrip() + "\n\n…"


def format_pr(pr: dict) -> str:
    number = pr.get("number")
    title = (pr.get("title") or "").strip()
    body = truncate_body(pr.get("body") or "")

    lines = [f"### PR #{number}: {title}", ""]
    if body:
        lines.append(body)
        lines.append("")
    return "\n".join(lines)


def collect_prs(prev_tag: str | None) -> list[dict]:
    commits = commits_in_range(prev_tag)
    if not commits:
        return []

    by_number: dict[int, dict] = {}

    for pr in list_merged_prs():
        merge_oid = (pr.get("mergeCommit") or {}).get("oid")
        if merge_oid and merge_oid in commits:
            by_number[pr["number"]] = pr

    for number in pr_numbers_from_commit_subjects(commit_subjects(prev_tag)):
        if number in by_number:
            continue
        pr = view_pr(str(number))
        if pr is None:
            continue
        merge_oid = (pr.get("mergeCommit") or {}).get("oid")
        if merge_oid and merge_oid in commits:
            by_number[number] = pr

    return [by_number[key] for key in sorted(by_number)]


def main() -> int:
    prev_tag = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else None

    try:
        prs = collect_prs(prev_tag)
    except (subprocess.CalledProcessError, FileNotFoundError, OSError) as error:
        print(f"warning: could not collect PR context: {error}", file=sys.stderr)
        return 0

    if not prs:
        print("No merged pull requests were found for this release range.")
        return 0

    print("\n".join(format_pr(pr) for pr in prs).rstrip())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
