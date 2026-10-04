#!/usr/bin/env python3
"""Require successful Win64/Linux qualification evidence for one exact SHA."""
from __future__ import annotations

import argparse
import json
import os
from urllib.parse import urlencode
from urllib.request import Request, urlopen


def request_json(url: str, token: str) -> dict:
    request = Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    with urlopen(request, timeout=30) as response:
        return json.load(response)


def evidence_names(sha: str) -> set[str]:
    return {
        f"qualification-linux-x86-64-{sha}",
        f"qualification-win64-x86-64-{sha}",
    }


def select_run(
    runs: list[dict],
    artifacts_by_run: dict[int, list[dict]],
    sha: str,
) -> tuple[int, set[str]] | None:
    expected = evidence_names(sha)
    candidates = sorted(
        (
            run
            for run in runs
            if run.get("head_sha") == sha
            and run.get("status") == "completed"
            and run.get("conclusion") == "success"
        ),
        key=lambda run: int(run["id"]),
        reverse=True,
    )
    for run in candidates:
        names = {
            artifact["name"]
            for artifact in artifacts_by_run.get(int(run["id"]), [])
            if not artifact.get("expired", False)
        }
        if expected <= names:
            return int(run["id"]), names
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", required=True, help="owner/name")
    parser.add_argument("--sha", required=True)
    parser.add_argument("--workflow", default="qualification.yml")
    parser.add_argument("--api-url", default=os.environ.get("GITHUB_API_URL", "https://api.github.com"))
    parser.add_argument("--token-env", default="GH_TOKEN")
    args = parser.parse_args()
    token = os.environ.get(args.token_env)
    if not token:
        raise SystemExit(f"{args.token_env} is required")
    query = urlencode({"head_sha": args.sha, "status": "completed", "per_page": 100})
    base = f"{args.api_url}/repos/{args.repository}"
    runs = request_json(
        f"{base}/actions/workflows/{args.workflow}/runs?{query}",
        token,
    ).get("workflow_runs", [])
    artifacts_by_run = {
        int(run["id"]): request_json(
            f"{base}/actions/runs/{run['id']}/artifacts?per_page=100",
            token,
        ).get("artifacts", [])
        for run in runs
        if run.get("head_sha") == args.sha
        and run.get("status") == "completed"
        and run.get("conclusion") == "success"
    }
    selected = select_run(runs, artifacts_by_run, args.sha)
    if selected is None:
        expected = ", ".join(sorted(evidence_names(args.sha)))
        raise SystemExit(
            f"QUALIFICATION_EVIDENCE_MISSING sha={args.sha} expected={expected}"
        )
    run_id, _ = selected
    print(f"QUALIFICATION_EVIDENCE_PASS sha={args.sha} run_id={run_id}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
