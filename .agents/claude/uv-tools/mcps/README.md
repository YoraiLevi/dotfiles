# mcps

Collection of MCP (Model Context Protocol) servers for Claude Code. One installable Python project hosts a shared base plus a launcher; each MCP server lives in its own subdirectory and is discovered at runtime.

## Layout

```
mcps/
├── pyproject.toml      # one installable project
├── mcp_common/         # installed package (shared base + launcher)
│   ├── __init__.py
│   ├── base.py         # create_server() helper
│   └── launcher.py     # mcps-run entry point
├── ping/               # demo MCP — discovered at runtime
│   └── server.py
├── pong/               # demo MCP — discovered at runtime
│   └── server.py
└── README.md
```

## Design

- **`mcp_common`** is the only installed Python package. It exports:
  - `create_server(name)` — returns a `FastMCP` with stderr-routed logging.
  - The `mcps-run` console script (entry point `mcp_common.launcher:main`).
- **Each MCP** is a subdirectory with a `server.py` that exposes a module-level `mcp` FastMCP instance.
- **The launcher** scans `MCPS_ROOT` (env var; defaults to this directory) for subdirectories with a `server.py` and loads them via `importlib.util`. No installation is required when a new MCP is added.

## Install

From this directory:

```powershell
uv tool install .
```

This makes `mcps-run` available on PATH. To pick up changes to `mcp_common`, reinstall with `--force --reinstall`. Changes to individual MCP `server.py` files take effect immediately on next launch (no reinstall needed).

## Add a new MCP

1. Create `mcps/myservice/server.py`:

   ```python
   from mcp_common import create_server

   mcp = create_server("myservice")

   @mcp.tool()
   def hello(name: str) -> str:
       """Greet someone by name."""
       return f"hello, {name}"
   ```

2. Register it in `~/.claude/settings.json`:

   ```json
   "mcpServers": {
     "myservice": { "command": "mcps-run", "args": ["myservice"] }
   }
   ```

3. Restart Claude Code. The tool appears as `mcp__myservice__hello`.

## Configuration

- `MCPS_ROOT` (env var) — override the discovery directory. Defaults to the absolute path baked into `launcher.py` at scaffold time.

## Demo

Two MCPs (`ping`, `pong`) and an agent (`ping-pong`) are shipped as a working example.

```powershell
mcps-run                  # lists discovered MCPs
mcps-run ping             # starts the ping server (waits on stdin for MCP protocol)
```
