# Coherent Grok for ADHD

On **Stop**, restyle the last assistant message in a **child** Grok process. The parent stays stock. Speech lives only in the child's `prompt.md`.

Stop cannot edit the first bubble. A restyle is a continuation: the parent is told to emit the rewrite verbatim.

## Install

```bash
grok plugin install <git-or-path> --trust
grok plugin enable coherent-grok-for-adhd
```

Plugins under `~/.grok/plugins/` are auto-trusted. Enable still required.

`GROK_PLUGIN_ROOT` is how the Stop hook finds `prompt.md` and the script.

One Stop entry on Windows and Unix: `sh scripts/stop-restyle` first (POSIX, needs `python3` or `python`), else `pwsh` + `scripts/stop-restyle.ps1`. PowerShell is not required on macOS or Linux.

## What it does

1. Stop fires with `reason=end_turn` and a long last assistant message.
2. The hook spawns a child Grok: `--system-prompt-override` is this plugin's `prompt.md` only, `--effort low`, `--max-turns 1`, `--no-subagents`, `--output-format json`.
3. The child uses an isolated `GROK_HOME` under the plugin data dir, plus `GROK_RESTYLE_CHILD=1`, so it does not load your hooks, skills, or rules, and does not fire Stop again.
4. The hook injects Stop `additionalContext`:

```
Output the following text verbatim as your user-facing reply. No preamble.

<rewritten message>
```

That prefix is required. Without it, the rewrite is stored as a user message and the parent may treat it as agreement and start new work.

The child rewrites only. It keeps numbers, paths, names, and caveats. It shortens recap and hedging. Verdict first. One fact per line. It returns only the rewritten message.

## Skip (no child, allow stop)

- Source shorter than about 80 characters
- Already simple: under 600 characters, **or** at least 3 non-empty lines with 70% of them ≤ 90 characters and total ≤ 2500
- Last ~800 characters match `want me to` / `shall I` / `should I` / `need from you` then `?` within 240 characters (do not restyle a close that asks whether to implement)
- `GROK_RESTYLE_CHILD` is set, cwd is the restyle home, `stopHookActive` is true, `subagentType` is set, or `reason` is not `end_turn`

A one-paragraph wall still restyles.

Failures fail open. The hook never prints `prompt.md` to stdout.

## Child binary

1. `GROK_REAL` if set
2. Else `grok` on `PATH` (stock)

If `PATH` grok is a shim that injects `--system-prompt-override` or re-fires Stop, set `GROK_REAL` to the unwrapped binary and keep the isolated child home.

## Without plugin install

Copy `hooks/hooks.json` into `~/.grok/hooks/`, keep `prompt.md` next to `scripts/`. Leave the Stop command as shipped (`sh` then `pwsh`). The script finds `prompt.md` beside the plugin root if `GROK_PLUGIN_ROOT` is unset. A zip of those files is in `dist/`.

## Not included

No parent skill. No project-rules speech file. No PATH wrapper. Plugins ship files, not `grok`.
