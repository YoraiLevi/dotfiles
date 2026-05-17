"""Ping MCP server. Exposes a single `ping` tool that returns 'ping'."""
from mcp_common import create_server

mcp = create_server("ping")


@mcp.tool()
def ping() -> str:
    """Return the literal string 'ping'.

    Used by the ping-pong agent to initiate a rally.
    """
    return "ping"
