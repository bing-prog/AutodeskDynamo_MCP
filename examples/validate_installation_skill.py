import argparse
import asyncio
import json
from datetime import datetime

import websockets

WS_URI = "ws://127.0.0.1:65296"


async def call_tool(tool_name: str, arguments: dict) -> tuple[bool, dict | str]:
    request = {
        "jsonrpc": "2.0",
        "method": "tools/call",
        "params": {
            "name": tool_name,
            "arguments": arguments,
        },
        "id": 1,
    }
    try:
        async with websockets.connect(WS_URI) as ws:
            await ws.send(json.dumps(request))
            raw = await ws.recv()
            data = json.loads(raw)
            if "error" in data:
                return False, data["error"]
            return True, data.get("result", "")
    except Exception as exc:
        return False, str(exc)


def parse_workspace_result(result: object) -> dict:
    if isinstance(result, dict):
        return result
    if isinstance(result, list) and result:
        first = result[0]
        if isinstance(first, dict) and "text" in first:
            return json.loads(first["text"])
    text = str(result)
    return json.loads(text)


async def run_validation(revit_version: str) -> dict:
    report = {
        "timestamp": datetime.now().isoformat(timespec="seconds"),
        "revit_version": revit_version,
        "steps": {},
        "pass": False,
    }

    ok, stats = await call_tool("get_server_stats", {})
    report["steps"]["get_server_stats"] = {"ok": ok, "result": stats}
    if not ok:
        report["reason"] = "get_server_stats call failed"
        return report

    stats_obj = parse_workspace_result(stats)
    active_sessions = int(stats_obj.get("active_sessions", 0))
    report["active_sessions"] = active_sessions
    if active_sessions <= 0:
        report["reason"] = "No active Dynamo connections"
        return report

    ok, before = await call_tool("analyze_workspace", {})
    report["steps"]["analyze_before"] = {"ok": ok, "result": before}
    if not ok:
        report["reason"] = "analyze_workspace before failed"
        return report
    before_obj = parse_workspace_result(before)
    before_count = int(before_obj.get("nodeCount", 0))

    instructions = {
        "nodes": [
            {
                "id": f"skill_validation_{revit_version}",
                "name": "Number",
                "value": "Point.ByCoordinates(1,2,3);",
                "x": 120,
                "y": 120,
            }
        ],
        "connectors": [],
    }
    ok, execute = await call_tool(
        "execute_dynamo_instructions", {"instructions": json.dumps(instructions)}
    )
    report["steps"]["execute"] = {"ok": ok, "result": execute}
    if not ok:
        report["reason"] = "execute_dynamo_instructions failed"
        return report

    ok, after = await call_tool("analyze_workspace", {})
    report["steps"]["analyze_after"] = {"ok": ok, "result": after}
    if not ok:
        report["reason"] = "analyze_workspace after failed"
        return report
    after_obj = parse_workspace_result(after)
    after_count = int(after_obj.get("nodeCount", 0))

    report["node_count_before"] = before_count
    report["node_count_after"] = after_count
    report["pass"] = after_count > before_count
    if not report["pass"]:
        report["reason"] = "nodeCount did not increase"
    return report


def save_report(report: dict, output_path: str) -> None:
    with open(output_path, "w", encoding="utf-8") as file:
        json.dump(report, file, indent=2, ensure_ascii=False)


def build_output_path(revit_version: str) -> str:
    sanitized = revit_version.replace(".", "_")
    return f"tests/temp/skill_validation_revit_{sanitized}.json"


async def main() -> None:
    parser = argparse.ArgumentParser(description="Validate Autodesk Dynamo MCP installation skill")
    parser.add_argument("--revit", required=True, help="Revit version label, e.g. 2021")
    args = parser.parse_args()

    report = await run_validation(args.revit)
    output_path = build_output_path(args.revit)
    save_report(report, output_path)

    print(json.dumps(report, ensure_ascii=False, indent=2))
    print(f"[INFO] report saved to: {output_path}")


if __name__ == "__main__":
    asyncio.run(main())
