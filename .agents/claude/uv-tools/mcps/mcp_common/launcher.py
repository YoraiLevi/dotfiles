"""Launcher entry point for the mcps monorepo.

Discovers MCP servers in MCPS_ROOT and runs the one named on argv[1].

Usage:
    mcps-run               -> print discovered MCP names to stderr
    mcps-run <name>        -> start the named server (blocks on stdio)
"""
from __future__ import annotations

import importlib.util
import os
import sys
from pathlib import Path

DEFAULT_MCPS_ROOT = Path(r"C:\Users\devic\.agents\claude\uv-tools\mcps")
RESERVED_DIRS = {"mcp_common", "__pycache__", ".git", "dist", "build"}


def mcps_root() -> Path:
    override = os.environ.get("MCPS_ROOT")
    return Path(override) if override else DEFAULT_MCPS_ROOT


def discover() -> list[str]:
    root = mcps_root()
    if not root.is_dir():
        return []
    found: list[str] = []
    for entry in root.iterdir():
        if not entry.is_dir():
            continue
        if entry.name in RESERVED_DIRS or entry.name.startswith((".", "_")):
            continue
        if (entry / "server.py").is_file():
            found.append(entry.name)
    return sorted(found)


def load_server(name: str):
    server_path = mcps_root() / name / "server.py"
    if not server_path.is_file():
        raise FileNotFoundError(f"No server.py for MCP '{name}' at {server_path}")
    spec = importlib.util.spec_from_file_location(f"mcps_dyn_{name}", server_path)
    if spec is None or spec.loader is None:
        raise ImportError(f"Could not load spec for {server_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    mcp = getattr(module, "mcp", None)
    if mcp is None:
        raise AttributeError(
            f"{server_path} must expose a module-level `mcp` FastMCP instance"
        )
    return mcp


def main() -> None:
    available = discover()
    if len(sys.argv) < 2:
        print("Usage: mcps-run <name>", file=sys.stderr)
        print(f"MCPS_ROOT: {mcps_root()}", file=sys.stderr)
        if available:
            print(f"Discovered MCPs: {', '.join(available)}", file=sys.stderr)
        else:
            print("No MCPs discovered.", file=sys.stderr)
        sys.exit(0 if available else 2)
    name = sys.argv[1]
    if name not in available:
        print(
            f"Unknown MCP '{name}'. Discovered: {', '.join(available) or '(none)'}",
            file=sys.stderr,
        )
        sys.exit(2)
    load_server(name).run()
