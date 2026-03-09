#!/usr/bin/env python3
"""Extract structured findings from review/audit logs into JSONL."""

from __future__ import annotations

import argparse
import json
import re
from datetime import datetime, timezone
from pathlib import Path

FAIL_TOKENS = {"REVIEW_FAIL", "AUDIT_FAIL"}
PASS_TOKENS = {"REVIEW_PASS", "AUDIT_PASS"}
SEVERITY_ORDER = {"low": 1, "medium": 2, "high": 3, "critical": 4}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Extract findings from review/audit logs."
    )
    parser.add_argument("--log-file", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--source", required=True)
    parser.add_argument("--mode", required=True)
    return parser.parse_args()


def normalize_severity(value: str | None) -> str:
    if not value:
        return "medium"
    normalized = value.strip().lower()
    return normalized if normalized in SEVERITY_ORDER else "medium"


def trim_text(value: str, limit: int = 800) -> str:
    value = re.sub(r"\s+", " ", value).strip()
    if len(value) <= limit:
        return value
    return value[: limit - 3].rstrip() + "..."


def parse_finding_json_payload(payload: str) -> dict[str, object] | None:
    try:
        obj = json.loads(payload)
    except json.JSONDecodeError:
        return None

    if not isinstance(obj, dict):
        return None

    title = trim_text(str(obj.get("title", "Untitled finding")), 160)
    severity = normalize_severity(str(obj.get("severity", "medium")))
    evidence = trim_text(str(obj.get("evidence", "No evidence provided.")), 1200)
    file_path = trim_text(str(obj.get("file", "")), 300)
    fix_hint = trim_text(str(obj.get("fix_hint", "No fix hint provided.")), 400)
    task_link = trim_text(str(obj.get("task_link", "")), 120)

    finding: dict[str, object] = {
        "title": title,
        "severity": severity,
        "evidence": evidence,
        "file": file_path,
        "fix_hint": fix_hint,
        "task_link": task_link,
    }

    if "accepted_risk" in obj:
        finding["accepted_risk"] = bool(obj.get("accepted_risk"))
    if obj.get("accepted_risk_reason"):
        finding["accepted_risk_reason"] = trim_text(
            str(obj.get("accepted_risk_reason")), 300
        )
    if obj.get("accepted_risk_until"):
        finding["accepted_risk_until"] = trim_text(
            str(obj.get("accepted_risk_until")), 60
        )

    return finding


def fallback_finding_from_failure(
    log_lines: list[str], source: str, mode: str
) -> dict[str, object]:
    tail = "\n".join(log_lines[-40:]).strip()
    if not tail:
        tail = "No additional log content available."
    return {
        "title": f"{source} {mode} review failed without structured findings",
        "severity": "medium",
        "evidence": trim_text(tail, 1200),
        "file": "",
        "fix_hint": "Review the corresponding log and emit FINDING_JSON lines with actionable remediation.",
        "task_link": "",
    }


def main() -> int:
    args = parse_args()
    log_path = Path(args.log_file)
    output_path = Path(args.output)

    if not log_path.is_file():
        return 0

    lines = log_path.read_text(encoding="utf-8", errors="ignore").splitlines()
    findings: list[dict[str, object]] = []
    fail_seen = False

    for raw_line in lines:
        line = raw_line.strip()
        if line in FAIL_TOKENS:
            fail_seen = True
        if line.startswith("FINDING_JSON:"):
            payload = line.split("FINDING_JSON:", 1)[1].strip()
            parsed = parse_finding_json_payload(payload)
            if parsed:
                findings.append(parsed)

    if fail_seen and not findings:
        findings.append(fallback_finding_from_failure(lines, args.source, args.mode))

    output_path.parent.mkdir(parents=True, exist_ok=True)
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    with output_path.open("w", encoding="utf-8") as handle:
        for finding in findings:
            enriched = {
                "source": args.source,
                "mode": args.mode,
                "ts_utc": now,
                **finding,
            }
            handle.write(json.dumps(enriched, ensure_ascii=True) + "\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
