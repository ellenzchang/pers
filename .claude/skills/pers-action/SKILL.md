---
name: pers-action
description: Use when the user wants to add, create, or update a Claude Quest action for the repo they are working in, e.g. "add a pers action to run this", "add a claude-quest action", "make an action for the build", "save this command in claude quest".
---

# Claude Quest actions

Claude Quest (the macOS app) keeps saved shell commands, called actions, in `~/Library/Application Support/ClaudeQuest/actions.json`, a JSON array. The app watches the file and reloads it, so an action added here shows up in the ACTIONS panel (⇧⌘A) of a running app without a restart.

## Action fields

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | Uppercase UUID, e.g. from `uuidgen`. |
| `repo` | no | Absolute path of the repo's **main checkout**, which all its worktrees share. Omit for a global action. |
| `command` | yes | Shell script, run with the session's directory as cwd. Multi-line is fine. |
| `nickname` | no | Display name. Without one the command is shown. |
| `environment` | no | `KEY=value` lines (one string, `\n` separated), exported before the command. |
| `readyMarker` | no | Output text that means a long-running command, like a server, has finished starting. |
| `choices` | no | Options, one per line. Running asks which one and exports it as `$CHOICE`. |

Omit unused optional fields.

## Steps

1. Work out what the action should run. Read the repo (`package.json`, `Makefile`, `pom.xml`, README, existing scripts) rather than guessing. If the user's intent is unclear, ask.
2. Find the repo path: `git worktree list --porcelain | head -1`, taking the first `worktree` entry. Do not use `--show-toplevel`, which returns the worktree you happen to be in.
3. Fill in the fields:
   - Give a short `nickname` for anything non-trivial.
   - For servers or watchers, set `readyMarker` to a line the command prints once it is up.
   - If a command varies by something like brand or environment, use `choices` and `$CHOICE` instead of several near-duplicate actions.
   - Never put a literal secret in `environment`: the file is plain text and readable by Claude's tools. Look it up instead, e.g. `DB_PASSWORD=$(secret get …)` or `$(security find-generic-password -s name -w)`.
4. Show the user the action you intend to add and wait for approval.
5. Read `actions.json` first. If an action with the same `repo` and `nickname` exists, update it in place and keep its `id`. Otherwise append. Write atomically and preserve every other entry, using `jq` (build the new object with `jq -n --arg …`, then write to a temp file and `mv` it over `actions.json`).
6. Verify with `jq . actions.json` that the file is still valid and contains the new action, then tell the user it will appear in the app's ACTIONS panel for this repo.

## Example

```json
{
  "id": "C967F5C8-D060-4428-8D2C-969D422068C8",
  "repo": "/Users/me/dev/my-service",
  "nickname": "run dev",
  "command": "npm run dev",
  "environment": "PORT=3000",
  "readyMarker": "Server listening"
}
```
