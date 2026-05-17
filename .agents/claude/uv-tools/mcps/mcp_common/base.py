"""Shared base for MCP servers in this monorepo."""
from __future__ import annotations

import logging
import sys

from mcp.server.fastmcp import FastMCP


def create_server(name: str) -> FastMCP:
    """Return a FastMCP instance with stderr-routed logging.

    stdout is reserved for the MCP JSON-RPC protocol when the server
    runs under Claude Code, so any logging must go to stderr.
    """
    logging.basicConfig(
        level=logging.INFO,
        format=f"[{name}] %(levelname)s: %(message)s",
        stream=sys.stderr,
    )
    return FastMCP(name)
