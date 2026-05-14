# Zellij config

Cross-platform [zellij](https://zellij.dev) config. Same `config.kdl` works on
Windows, macOS, and Linux — no per-OS edits, no path hardcoding.

## Per-machine setup (one-time)

Install the dispatcher as a [uv tool](https://docs.astral.sh/uv/concepts/tools/).
This puts a real `zellij-dispatch` binary on `PATH`, the same way on every OS:

```sh
uv tool install --editable ~/.config/zellij
```

`--editable` means edits to `dispatch.py` take effect immediately without
reinstall. On Windows, run the same command from PowerShell / Git Bash.

If `zellij-dispatch` isn't found after install, run `uv tool update-shell`
once to add uv's tool-bin dir to `PATH`.

## Runtime dependencies


| OS  | Required                                                                                                                                              |
| --- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| All | `uv` (one-time install: [https://docs.astral.sh/uv/getting-started/installation/](https://docs.astral.sh/uv/getting-started/installation/)), `zellij` |


`uv` handles Python — you don't need to install Python yourself. Both `launch-profile` and `switch-session` are implemented in Python stdlib only and need no external tools (no `fzf`, no `pwsh`/`bash`).

## What the keybinds do


| Key             | Action                                                                                                |
| --------------- | ----------------------------------------------------------------------------------------------------- |
| `Ctrl+Shift+A`  | Session switcher — list zellij sessions, switch / delete / create                                     |
| `Ctrl+Shift+` ` | Profile launcher — pick from `profiles.json` (+ Windows Terminal merge on Windows), open in a new tab |


Both open in a floating pane. Both work the same on all three OSes.

### Picker controls

Both pickers are rendered in pure Python (stdlib only — no `fzf` dependency).
Shared controls:


| Key                      | Action                                    |
| ------------------------ | ----------------------------------------- |
| `↑` / `↓` (or `k` / `j`) | Move selection up / down (wraps at edges) |
| `Home` / `End`           | Jump to first / last entry                |
| `Enter`                  | Accept the highlighted entry              |
| `1`-`9`, `0`             | Jump to entry 1-9 or 10 (instant accept)  |
| `Esc`, `q`, or `Ctrl-C`  | Cancel                                    |


Extra controls inside `switch-session`:


| Key      | Action                                                                                                                 |
| -------- | ---------------------------------------------------------------------------------------------------------------------- |
| `Ctrl-D` | Delete the highlighted session. If it has active clients, prompts `Kill it? [y/N]`. Cannot delete the current session. |
| `Ctrl-N` | Create a new session — prompts for a name, then switches to it                                                         |


When stdin isn't a TTY (e.g. piped input, CI), each picker degrades to a
line-based mode: type a number (or, for `launch-profile`, a substring), press
Enter. Ctrl-D / Ctrl-N aren't available in the fallback.

## How it works

```
zellij           (reads config.kdl)
  └─→ Run "zellij-dispatch" "<action>"
        └─→ ~/.local/bin/zellij-dispatch[.exe]     (uv-installed entry point, on PATH)
            └─→ python -m dispatch                  (calls dispatch.main)
                ├─ Action in HANDLERS dict?  → run Python handler inline
                └─ Otherwise                  → spawn scripts/<action>.{ps1,sh}
```

Two dispatch paths, in priority order:

1. **Python handler** (`HANDLERS` dict in `dispatch.py`). Used by both
  `launch-profile` and `switch-session` today; needs no external tools.
2. **Script fallback** — `scripts/<action>.ps1` on Windows or
  `scripts/<action>.sh` on POSIX. Kept in place for future shell-only actions
   (no current users; `scripts/` may be empty).

Either path is fine for a new action. The naming convention (file basename
or `HANDLERS` key) **is** the registry — no central table to maintain.

### Why a uv-installed entry point

Zellij's keybind `Run` block does not expand `~`, `$HOME`, or `%USERPROFILE%`
in either the binary path or its arguments. Its `cwd` field is silently
ignored when the path can't be resolved. The only env-aware mechanism zellij
honors is `PATH` lookup of the bare binary name.

`uv tool install` builds a real executable (`.exe` on Windows, native binary
on POSIX) and places it on `PATH`. Zellij looks up `zellij-dispatch` the same
way it looks up `git` or `zellij` itself — no path expansion, no shell shim,
no host-specific config. See [zellij issues #2574](https://github.com/zellij-org/zellij/issues/2574),
[#2288](https://github.com/zellij-org/zellij/issues/2288), and
[#4527](https://github.com/zellij-org/zellij/issues/4527) for the background.

## Adding a new action

**Option A — Python handler** (cross-platform stdlib, no extra processes):

1. Add a function to `dispatch.py`: `def my_action(args: list[str]) -> int: ...`
2. Register it: `HANDLERS["my-action"] = my_action`
3. Wire the keybind (see below). Done; `--editable` mode picks it up.

**Option B — Shell script** (when you want pwsh/bash, or external tools like
fzf):

1. Drop `scripts/<my-action>.ps1` and/or `scripts/<my-action>.sh`. Either is
  optional — the dispatcher errors with a clear message if the impl for the
   current OS is missing.
2. On POSIX: `chmod +x scripts/<my-action>.sh`.
3. Wire the keybind. Done; auto-discovered by glob.

**Wiring the keybind** (both options use the same form):

```kdl
bind "Ctrl Shift x" {
    Run "zellij-dispatch" "<my-action>" {
        floating true
        close_on_exit false
        name "My Action"
        width "60%"
        height "40%"
    }
    SwitchToMode "locked"
}
```

Reload zellij config. No reinstall of the dispatcher needed.

## Profile registry (`profiles.json`)

`launch-profile` reads `profiles.json`. Each entry may declare per-OS variants
under `windows` / `macos` / `linux` keys; an entry is visible on an OS only
if it has a key for that OS. Fields per OS: `command` (array, required),
`cwd` (string, optional, supports `~`), `env` (object, optional).

```json
{
  "profiles": [
    { "name": "PowerShell", "windows": { "command": ["pwsh", "-NoLogo"] } },
    { "name": "zsh",        "macos":   { "command": ["zsh", "-l"] },
                            "linux":   { "command": ["zsh", "-l"] } }
  ]
}
```

### Windows: merged with Windows Terminal profiles

On Windows, `launch-profile` also reads
`%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json`
and merges the WT profile list into the picker. WT-sourced entries get a
subtle  `[wt]` suffix in the fzf list so you can tell them apart.

- **Order**: `profiles.json` entries first, then WT entries.
- **Conflict policy**: if a name appears in both, `profiles.json` wins — that
's how you override / shadow a WT profile's behavior under zellij.
- **Graceful degradation**: if WT isn't installed (no `settings.json`), only
`profiles.json` is used; if the WT JSON fails to parse, a warning is
emitted but the launcher still works with whatever it could read.

Update WT profiles → they automatically appear in `Ctrl+Shift+`. No
duplication required.

## Maintenance

- **Edit the dispatcher**: just edit `dispatch.py`; `--editable` mode picks
up changes immediately. No reinstall needed.
- **Upgrade Python**: `uv` manages a venv for the tool with its own Python.
To rebuild the venv (e.g. after `requires-python` change): `uv tool install --reinstall --editable ~/.config/zellij`.
- **Uninstall**: `uv tool uninstall zellij-dispatch`.
- **List installed tools**: `uv tool list`.

