"""Pong MCP server. Exposes a single `pong` tool that returns 'pong'."""
from mcp_common import create_server

mcp = create_server("pong")


@mcp.tool()
def pong() -> str:
    """Return the literal string 'pong'.

    Used by the ping-pong agent to respond to a ping.
    """
    return "pong"
