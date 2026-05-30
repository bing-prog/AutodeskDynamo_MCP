import argparse
import json
from pathlib import Path


def extract_session_id(report: dict) -> str:
    result = report.get("steps", {}).get("analyze_after", {}).get("result", "")
    if isinstance(result, str):
        try:
            parsed = json.loads(result)
            return str(parsed.get("sessionId", ""))
        except Exception:
            return ""
    return ""


def extract_process_id(report: dict) -> str:
    result = report.get("steps", {}).get("analyze_after", {}).get("result", "")
    if isinstance(result, str):
        try:
            parsed = json.loads(result)
            return str(parsed.get("processId", ""))
        except Exception:
            return ""
    return ""


def main() -> None:
    parser = argparse.ArgumentParser(description="Validate multi-version installation reports")
    parser.add_argument("--versions", nargs="+", required=True, help="Revit versions, e.g. 2021 2024 2026")
    args = parser.parse_args()

    reports = []
    for version in args.versions:
        file_path = Path(f"tests/temp/skill_validation_revit_{version}.json")
        if not file_path.exists():
            print(f"[FAIL] Missing report: {file_path}")
            return
        with file_path.open("r", encoding="utf-8") as file:
            report = json.load(file)
        reports.append(report)

    all_pass = all(bool(report.get("pass")) for report in reports)
    sessions = [extract_session_id(report) for report in reports]
    processes = [extract_process_id(report) for report in reports]

    print("=== Installation Skill Report Validation ===")
    for report, session, process in zip(reports, sessions, processes):
        print(
            f"Revit {report.get('revit_version')}: "
            f"PASS={report.get('pass')} "
            f"active_sessions={report.get('active_sessions')} "
            f"sessionId={session} processId={process}"
        )

    unique_sessions = len({session for session in sessions if session})
    unique_processes = len({process for process in processes if process})

    print()
    print(f"[INFO] all_pass={all_pass}")
    print(f"[INFO] unique_session_count={unique_sessions}")
    print(f"[INFO] unique_process_count={unique_processes}")

    if not all_pass:
        print("[FAIL] Functional validation failed in at least one report.")
        return

    if unique_sessions < len(reports) or unique_processes < len(reports):
        print("[WARNING] Reports appear to come from the same Dynamo session/process.")
        print("[WARNING] This proves skill workflow works, but not full cross-version switching.")
        return

    print("[OK] Reports indicate independent sessions/processes across versions.")


if __name__ == "__main__":
    main()
