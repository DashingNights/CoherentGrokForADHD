# Coherent Grok for ADHD

On **Stop**, restyle the last assistant message in a **child** Grok process. The parent stays stock. Speech lives only in the child's `prompt.md`.

## Why stock output is hard to digest

ADHD working memory holds a few items at once. A normal assistant reply often asks you to hold all of these in one blob:

- A recap of the question you just typed
- Hedging (`you might want to`, `it's worth noting`, `great question`)
- The actual verdict, buried in the middle or the last sentence
- Three facts glued into one bullet with slashes and colons
- A caveat, a path, and a number in the same breath as the advice
- A pronoun (`this` / `the above`) that only makes sense if you still have the previous sentence on screen

You do not fail to read. You run out of slots before you can **infer the decision**. The paragraph looks like one unit, so you cannot keep the verdict, drop the recap, and still have the path. Slash-packing is worse: `85% index / 15% satellite / cash when the latch fires` looks like one fact. It is four. Miss the latch and you inferred the wrong book.

A one-paragraph wall is the failure mode this plugin targets. Short, already-clean answers are left alone.

## What we change

We do not change how Grok thinks, which tools it uses, or the parent system prompt. After the turn stops, a **child** Grok rewrites only the last assistant message.

- **Verdict first.** Slot one is the decision, not the recap.
- **One fact per line.** If a bullet wraps, it splits. You can skip a line without losing the next.
- **Keep every number, path, name, and caveat.** Brevity must not delete the thing you needed.
- **Cut recap and hedging only.** No new facts. No new work.

The first bubble is still the original. Stop cannot edit it. The restyle is a continuation you read instead.

### Example

Stock close (one breath, verdict last, recap first):

> Great question — managing time is really about managing focus. Because distractions are everywhere, you might want to consider turning off notifications and blocking your calendar. If you can protect attention for two hours a day, output can double. Also remember the verify step already runs `~/proj/scripts/check.sh`, and you should not skip that on a dirty tree.

Restyle:

> Protect two hours of attention a day and output can double.
>
> Focus is the scarce resource, not clock time.
>
> Do
>
> - Turn off notifications.
> - Block the calendar.
>
> Keep
>
> - Verify already runs `~/proj/scripts/check.sh`.
> - Do not skip verify on a dirty tree.

Same facts. Decision in the first line. Path still there. No “great question.”

A packed bullet:

> Mix: 85% index / 15% monthly skip-1m satellite (n=10, keep=20) / cash only when the latch fires.

becomes separate lines (index, satellite, cash, latch). You can hold one number at a time.

## How it works

1. You ask something. Grok answers in the parent session (stock).
2. The turn ends (`reason=end_turn`). The Stop hook runs.
3. If the answer is already short or already short-line, or it ends by asking whether to implement, the hook **allows stop**. No second bubble.
4. Otherwise it spawns a **child** Grok:
   - `--system-prompt-override` = this plugin's `prompt.md` only
   - `--effort low`, `--max-turns 1`, `--no-subagents`, `--output-format json`
   - `GROK_RESTYLE_CHILD=1`
   - Isolated `GROK_HOME` under the plugin data dir (no your hooks, skills, or rules; the child does not fire Stop again)
5. The child returns only the rewritten message.
6. The hook injects Stop `additionalContext`:

```
Output the following text verbatim as your user-facing reply. No preamble.

<rewritten message>
```

That prefix is required. Without it, the rewrite is stored as a user message and the parent may treat it as agreement and start new work.

7. The parent continues once and prints the rewrite. UI: original bubble, then **Stop hook feedback, continuing**, then the short reply.

`GROK_PLUGIN_ROOT` is how the hook finds `prompt.md` and the script.

One Stop entry on Windows and Unix: `sh scripts/stop-restyle` first (POSIX, needs `python3` or `python`), else `pwsh` + `scripts/stop-restyle.ps1`. PowerShell is not required on macOS or Linux.

## Install

```bash
grok plugin install <git-or-path> --trust
grok plugin enable coherent-grok-for-adhd
```

Plugins under `~/.grok/plugins/` are auto-trusted. Enable still required.

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
