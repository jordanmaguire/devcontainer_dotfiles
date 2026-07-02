---
name: diffx-review
description: Use when the user wants to review their local working-tree changes in a GitHub-style browser UI and hand the resulting inline comments back for action. Triggers on phrases like "start a diffx review", "review my changes in diffx", "open diffx", "pull my diffx comments", "action my review comments", "/diffx-review". Runs diffx (a local diff-review web server) against uncommitted changes — no commit or push required — then reads the comments back via its API and actions them.
---

# diffx-review

[diffx](https://github.com/wong2/diffx) is a local code-review tool: it serves the working-tree diff in a GitHub-like "Files changed" web UI where the user leaves inline comments, then exposes those comments over an HTTP API so a coding agent can read them back and action them. This skill drives both halves of that loop.

There are two phases. Detect which one the user wants from their words and from whether a server is already running (see step 0). Do **not** run both in one turn — starting a review hands control to the user to actually read the diff and comment; that takes real time.

- **Start** — "start a diffx review", "open diffx", "review these changes" → do **Phase A**.
- **Finish** — "pull my comments", "I'm done reviewing", "action my comments" → do **Phase B**.

## Operating principles

- **Working tree only, never commit or push.** The whole point is reviewing uncommitted work. This skill never commits, stages content, pushes, or rewrites history. The user's git state at the end must match the start (modulo the intent-to-add dance below, which is reversed on finish).
- **Surface new files.** diffx shows `git diff`, which omits untracked files — and agent-written *new* files are usually the most important to review. Make them visible with `git add -N` (intent-to-add), which records the path only, not content. Undo it on finish so untracked files stay untracked.
- **Action code, discuss questions.** A comment asking for a concrete change → make the change and resolve it. A comment asking a question, expressing a preference to debate, or explicitly deferred ("separate request", "follow up later") → answer it in chat and leave it **open**. Never resolve a comment you didn't actually act on in code.
- **Preserve the user's words when resolving.** The resolve call rewrites the comment; always send the original `body` back unchanged with `status: "resolved"`.
- **Match the codebase, not the comment's literal text.** A one-line comment ("format it like X") is a request, not a spec — verify the surrounding convention before applying, exactly as for any edit.

## Environment notes (learned; don't rederive)

- **Install:** a global `npm i -g diffx-cli` fails with `EACCES` on `/usr/local` in this container. Use `npx --yes diffx-cli` — it caches under `~/.npm/_npx`, so only the first run downloads.
- **Flags:** `--no-open` (suppress the browser launch; there is no `--no-port-open`), `--port <n>` (default `3433`). Pin `3433` for a predictable URL and API base.
- **Run it as the primary background process.** Do **not** background it with `&` *inside* another backgrounded shell — when that wrapper shell exits it kills the server. Launch `npx --yes diffx-cli --no-open --port 3433` directly as a `run_in_background` command with no trailing `&`.
- **Git args** pass after `--`: `diffx -- main..HEAD`, `diffx -- --cached`. Default (no args) = working-tree diff, which is what this skill wants.

## API contract (base `http://localhost:3433`)

| Call | Purpose |
|------|---------|
| `GET /api/diff` | `{ "patch": "<unified diff>" }` — use to confirm which files loaded. |
| `GET /api/comments` | JSON array of comments (see shape below). |
| `PUT /api/comments/{id}` | Body `{"body": "...", "status": "resolved"}` — resolve/edit. Send original body back. |
| `DELETE /api/comments/{id}` | Remove a comment. |

Note: unmatched `/api/*` paths return the SPA's `index.html` with HTTP 200, so probe by JSON `content-type`, not status code.

Comment shape:
```json
{ "id": "uuid", "filePath": "app/...", "side": "additions|deletions",
  "lineNumber": 22, "lineContent": "...", "body": "the user's note",
  "status": "open|resolved", "replies": [] }
```

## Phase A — start a review

1. **Repo check.** Confirm the cwd is a git repo (`git rev-parse --show-toplevel`). If not, stop and say so.
2. **Surface untracked files.** Snapshot them and mark intent-to-add:
   ```bash
   GITDIR=$(git rev-parse --git-dir)
   git ls-files --others --exclude-standard > "$GITDIR/diffx-intent-added"
   [ -s "$GITDIR/diffx-intent-added" ] && xargs -a "$GITDIR/diffx-intent-added" -r git add -N --
   ```
   (The snapshot file lets Phase B reverse exactly these, even in a later turn/session.)
3. **Reuse or launch.** Probe `GET /api/diff` (by JSON content-type). If a diffx server is already up on `3433`, reuse it. Otherwise launch `npx --yes diffx-cli --no-open --port 3433` as a background process and poll `GET /api/diff` until it returns 200 (a few seconds).
4. **Confirm the diff loaded.** Fetch `GET /api/diff`, list the files present, and check the intent-added new files appear. Report the count.
5. **Hand off.** Give the user the URL — **http://localhost:3433** — and tell them: VS Code usually auto-forwards the port (else forward `3433` in the Ports tab); review, leave inline comments, then say when they're done. Stop here — do not proceed to Phase B in the same turn.

## Phase B — pull and action comments

1. **Fetch.** `GET /api/comments`. If empty, say so and stop (after teardown, step 5). If the server isn't running, tell the user their session has ended and offer to restart Phase A.
2. **Triage each open comment.** Read the file at `filePath` around `lineNumber` for context (`side` tells you which side of the diff the line is on). Classify:
   - **Actionable change** → make the edit, matching surrounding conventions.
   - **Question / preference / explicitly deferred** → note it for a chat answer; leave open.
   Correct the user where warranted (e.g. a suggested snippet that wouldn't compile) rather than applying it blindly.
3. **Verify changes.** Run the project's linter/syntax check on files you edited (e.g. `rubocop`, `ruby -c` for this repo) before claiming done.
4. **Resolve only what you actioned.** For each actioned comment: `PUT /api/comments/{id}` with its original `body` and `status: "resolved"`. Leave questions/deferrals open so the board still shows them.
5. **Teardown of intent-to-add.** Restore untracked files to untracked so git state matches the start:
   ```bash
   GITDIR=$(git rev-parse --git-dir)
   [ -s "$GITDIR/diffx-intent-added" ] && xargs -a "$GITDIR/diffx-intent-added" -r git reset -q -- && rm -f "$GITDIR/diffx-intent-added"
   ```
   Leave the diffx server running unless the user asks to stop it (they may reload and add more comments).
6. **Report.** Summarize per comment: what changed and was resolved, and what you left open with your answer/recommendation. Tell the user to reload the diffx tab to see resolved comments update.

## When to stop and report instead of acting

- Not in a git repo.
- Phase B invoked but no diffx server is reachable (session ended) — offer to restart rather than guessing at comments.
- A comment asks for a change you believe is wrong or risky — apply nothing, explain, and leave it open for the user to decide.
- A comment is explicitly deferred ("separate request", "follow up") — never action it; acknowledge and move on.

## Things to avoid

- Don't `npm i -g` — use `npx`.
- Don't background the server inside another backgrounded shell (it dies with the wrapper).
- Don't stage file *content*, commit, or push — intent-to-add records paths only, and Phase B reverses it.
- Don't resolve a comment you only answered in chat.
- Don't rewrite a comment's body when resolving — echo it back verbatim.
