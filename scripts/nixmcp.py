#!/usr/bin/env python3
"""Minimal MCP stdio client for the `mcp-nixos` server.

CLAUDE.md mandates verifying Nix attrs/options through mcp-nixos. That server
speaks MCP JSON-RPC over stdio, so this wrapper does the handshake and exposes
two commands:

    nixmcp.py list                      # list available tools
    nixmcp.py call <tool> '<json-args>' # call a tool, print the text result

Example:
    nixmcp.py call nixos_search '{"query": "cudaPackages.cudnn", "type": "packages"}'
"""
from __future__ import annotations

import json
import subprocess
import sys

SERVER_CMD = ["mcp-nixos"]


def _send(proc, msg):
    proc.stdin.write(json.dumps(msg) + "\n")
    proc.stdin.flush()


def _read_until(proc, want_id):
    """Read newline-delimited JSON-RPC until a response with id==want_id."""
    for line in proc.stdout:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if obj.get("id") == want_id:
            return obj
    return None


def session(action, tool=None, args=None):
    proc = subprocess.Popen(
        SERVER_CMD, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL, text=True, bufsize=1,
    )
    try:
        _send(proc, {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": "2025-06-18", "capabilities": {},
            "clientInfo": {"name": "nixmcp", "version": "1.0"}}})
        _read_until(proc, 1)
        _send(proc, {"jsonrpc": "2.0", "method": "notifications/initialized"})

        if action == "list":
            _send(proc, {"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
            resp = _read_until(proc, 2)
            for t in (resp or {}).get("result", {}).get("tools", []):
                print(f"{t['name']}\n    {t.get('description','').splitlines()[0] if t.get('description') else ''}")
            return
        if action == "call":
            _send(proc, {"jsonrpc": "2.0", "id": 3, "method": "tools/call",
                         "params": {"name": tool, "arguments": args or {}}})
            resp = _read_until(proc, 3)
            res = (resp or {}).get("result", {})
            for block in res.get("content", []):
                if block.get("type") == "text":
                    print(block["text"])
            if res.get("isError"):
                sys.exit(2)
    finally:
        proc.terminate()


def main():
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(1)
    action = sys.argv[1]
    if action == "list":
        session("list")
    elif action == "call":
        tool = sys.argv[2]
        args = json.loads(sys.argv[3]) if len(sys.argv) > 3 else {}
        session("call", tool, args)
    else:
        print(__doc__); sys.exit(1)


if __name__ == "__main__":
    main()
