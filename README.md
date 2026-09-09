# Coherent Grok for ADHD

On **Stop**, a child Grok restyles the last assistant message.
The parent session stays stock, and the speech spec lives only in the child's `prompt.md`.

Map

- Must: install, what you see, skip rules
- Why: you can only hold a few things in mind at once
- Skip: child flags, manual zip, what we do not ship

## Why stock output is hard

ADHD working memory is small. You can only hold a few things in mind at once.

A stock reply often dumps all of these into one paragraph:

- Recap of the question you just typed
- Hedges: `you might want to`, `it's worth noting`, `great question`
- The actual answer, buried in the middle or the last sentence
- Three facts glued with slashes and colons
- A warning, a path, and a number in the same breath as the advice
- Words like `this` or `the above` that only make sense if the last sentence is still on screen

The paragraph looks like one lump. By the time you have the answer, the path is gone, and a reread still leaves you unsure what to do.

Gluing with slashes looks like one step and is four:

`Install Node 20 / run npm ci / run npm test / skip the production build on PRs`

Miss “skip the production build” and you ship a full build on every PR.

A long one-paragraph answer still restyles. Short answers that are already easy to scan are left alone.

## What the restyle does

The parent still thinks, tools, and prompts as stock Grok.
After the turn stops, a **child** rewrites only the last assistant message.

- **Answer first.** The first line is what to do.
- **One fact per line.** If a bullet wraps, split it.
- **Keep every number, path, name, and warning.**
- **Cut recap and hedging only.** Do not add facts or start new work.

Stop cannot edit the first bubble. The restyle is a continuation, so read that one.

### Example

Stock (verdict last, recap first):

> Great question — managing time is really about managing focus. Because distractions are everywhere, you might want to consider turning off notifications and blocking your calendar. If you can protect attention for two hours a day, output can double. Also remember the verify step already runs `~/proj/scripts/check.sh`, and you should not skip that on a dirty tree.

Restyle:

> Protect two hours of attention a day and output can double.
>
> Attention is what runs out.
>
> Do
>
> - Turn off notifications.
> - Block the calendar.
>
> Keep
>
> - Verify already runs `~/proj/scripts/check.sh`.
> - Do not skip verify if tests failed.

The restyle keeps the same facts. The first line is the answer, and the path is still there.

Packed bullet:

> Setup: Node 20 / `npm ci` / `npm test` / skip the production build on PRs.

Restyle:

> Setup
>
> - Node 20.
> - `npm ci`.
> - `npm test`.
> - Skip the production build on PRs.

## How it works

1. You ask. Parent Grok answers stock.
2. The turn ends (`reason=end_turn`). Stop runs.
3. Already short, already short-line, or a close that asks whether to implement: allow stop.
   No second bubble.
4. Else spawn a **child** Grok:
   - `--system-prompt-override` = this plugin's `prompt.md` only
   - `--effort low`
   - `--max-turns 1`
   - `--no-subagents`
   - `--output-format json`
   - `GROK_RESTYLE_CHILD=1`
   - Isolated `GROK_HOME` under the plugin data dir
5. Isolated home means the child skips your hooks, skills, and rules.
   The child does not fire Stop again.
6. The child returns only the rewritten message.
7. The hook injects Stop `additionalContext`:

```
Output the following text verbatim as your user-facing reply. No preamble.

<rewritten message>
```

That prefix is required. Without it, the rewrite is stored as a user message, and the parent may treat it as agreement and start new work.

8. The parent continues once and prints the rewrite.

What you see

- Original bubble
- **Stop hook feedback, continuing**
- Short reply

`GROK_PLUGIN_ROOT` is how the hook finds `prompt.md` and the script.

One Stop entry on Windows and Unix.

- First: `sh scripts/stop-restyle` (POSIX; needs `python3` or `python`)
- Else: `pwsh` + `scripts/stop-restyle.ps1`

macOS and Linux do not need PowerShell.

## Install

```bash
grok plugin install <git-or-path> --trust
grok plugin enable coherent-grok-for-adhd
```

Plugins under `~/.grok/plugins/` are auto-trusted, but enable is still required.

## Skip (no child, allow stop)

- Source shorter than about 80 characters
- Under 600 characters
- Or at least 3 non-empty lines, 70% of them ≤ 90 characters, total ≤ 2500
- Last ~800 characters match `want me to`, `shall I`, `should I`, or `need from you`
- Then `?` within 240 characters
- `GROK_RESTYLE_CHILD` is set
- cwd is the restyle home
- `stopHookActive` is true
- `subagentType` is set
- `reason` is not `end_turn`

Do not restyle a close that asks whether to implement.

Failures fail open, and the hook never prints `prompt.md` to stdout.

## Child binary

1. `GROK_REAL` if set
2. Else `grok` on `PATH` (stock)

If `PATH` grok injects `--system-prompt-override` or re-fires Stop, it is a shim. Set `GROK_REAL` to the unwrapped binary and keep the isolated child home.

## Without plugin install

Copy `hooks/hooks.json` into `~/.grok/hooks/` and keep `prompt.md` next to `scripts/`. Leave the Stop command as shipped (`sh` then `pwsh`). If `GROK_PLUGIN_ROOT` is unset, the script finds `prompt.md` beside the plugin root. A zip of those files is in `dist/`.

## Do not ship

- A parent skill
- A project-rules speech file
- A PATH wrapper

Plugins ship files, not `grok`.
