# Explore a local web UI for jm-review-picker

## Task

Find out whether the review picker should be drawn as a local web page instead of (or as well as) a Claude
Code pane, and build a working prototype if it is viable. Report back with a recommendation, the evidence for it,
and what the prototype does and does not do.

Do not change the `iex` repository (`/workspaces/iex`). All work lives under `~/dotfiles/claude/`.

## What the user wants from a review

A review skill (comment accuracy, class composition, and others to come) produces suggested edits. For each
review the user wants:

1. A numbered list of suggested changes.
2. For each change, a diff of the old and new text, so they can compare them.
3. For each change, a checkbox to say whether it should be applied.

Then one action sends the choices back to Claude, which applies only the ticked changes.

## What exists today

The `jm-review-picker` mod in `~/dotfiles/claude/mods/jm-review-picker/` does all of the above in a Claude Code pane. It
is loaded in every session through `CLAUDE_CODE_PLUGIN_DIRS` in `~/dotfiles/claude/settings.json`.

- `hooks/register.tsx` registers:
  - A tool, `mcp__jm-review-picker__propose_changes`, that Claude calls with `{ title, changes: [...] }`. Each change
    has a `reason` and is either an edit (`file`, `line`, `before`, `after`, `context_after?`), drawn as a diff, or a
    proposal (`proposal`, `files?`), drawn as a description. Numbers follow the order of `changes`, starting at 1.
  - The `jm-review` skill (`~/dotfiles/claude/skills/jm-review/`) is the caller: it runs each review and calls the tool.
  - A pane drawn with the mod UI elements (`Box`, `Text`, `Button`).
  - A `/jm-review-picker` command that reopens the pane.
- Pressing "Apply selected" calls `$.prompt.submit({ text, asUser: true })` with, e.g.:
  ```
  Apply these changes from the "Comment accuracy" review: 1, 3, 4.
  Skip: 2.
  ```
- `hooks/register.test.tsx` runs with `claude plugin test <mod folder>`; `claude plugin validate <mod folder>`
  checks the manifest and module. The `claude` binary is not on `PATH` in this container; it is at
  `~/.vscode-server/extensions/anthropic.claude-code-<version>-linux-arm64/resources/native-binary/claude`.

Keep the `propose_changes` input and the reply text above as the contract. Review skills are written against them,
so a web UI should replace only how the list is drawn and how the choice comes back.

## Why look at a web page

The user works in the VS Code extension. The pane there is limited:

- No custom HTML. The mod API's `Client` element (a region drawn by the plugin's own module) exists on the
  desktop app only; the VS Code element table is `Box`, `Text`, `Button`, `Input`, `Select`, `Svg`, `Link`, `Code`,
  `Markdown`.
- No checkbox element. Toggles are `Button`s labelled ☑ / ☐. A `Button` can hold only strings and `Text`, so an
  `Svg` checkbox cannot be the pressable part.
- Spacing is in text rows, not pixels.
- The `Code` element's `format: 'diff'` colouring was in doubt in VS Code, so diff lines are now `Text` with
  `backgroundColor` `diffAdded` / `diffRemoved`.

A web page would give real checkboxes, CSS layout, proper diff rendering (side by side or inline, word-level
highlights), and room for longer lists.

## Precedent to read first

`~/dotfiles/claude/skills/diffx-review/SKILL.md` drives a local web review UI (diffx) from Claude Code in this same
container. It documents the following, which has already been learned and should not be rederived:

- Launch the server as a `run_in_background` command with no trailing `&`. Backgrounding inside another background
  shell kills it when the wrapper exits.
- `npm i -g` fails with `EACCES`; `npx --yes <pkg>` works.
- VS Code usually auto-forwards the port; otherwise the user forwards it in the Ports tab.
- The two phases are separate turns: start (hand the URL over and stop), then finish (read results back).

## Environment

- Dev container, VS Code Remote, Claude Code VS Code extension 2.1.304 (arm64).
- Available: `node` 22, `python3`, `uv`, `npx`, and the `code` remote CLI. Not available: `bun`, `deno`, `rsync`.
- Several dev instances can run at once (the `iex` Traefik setup uses ports such as 3000, 5432, 6379 and 8020 plus
  N*100), so pick a port outside those or let the OS choose one.

## Questions to answer

1. How do the user's choices get back to Claude? Candidates, roughly from most to least integrated:
   - The mod hosts or supervises the server and, on submit, calls `$.prompt.submit` exactly as the pane does.
     Find out whether a mod can keep a long-running process (`$.process`, `$.clock.every` polling a result file or
     endpoint) and what happens on reload. The API is in the `plugin-authoring` skill's types file and
     `reference.md`; load that skill to get their paths.
   - The server writes a result file and Claude watches for it (the `Monitor` tool, or a background command that
     exits when the file appears, which re-invokes Claude).
   - The user says "done" and a skill reads the result over HTTP, as diffx-review does.
2. Can the page be opened for the user automatically, e.g. in VS Code's Simple Browser through the `code` CLI or a
   `vscode://` URL, or must they click a link? Check whether port forwarding is automatic for a port opened by a
   background process.
3. Is a separate browser tab worse than a pane next to the chat? Note what is lost: always visible, no
   context switch, no port.
4. Security: bind to `127.0.0.1` only. Consider a random per-review token in the URL so another local process
   cannot post a selection. Never put file contents in query strings or logs.
5. Can both coexist? For example, the pane stays the default and gains an "Open in browser" button, and
   `propose_changes` takes no new arguments.

## Constraints

- Stay dependency-light. Prefer Node's standard library or Python's `http.server` over a framework. If a package
  is needed, use `npx --yes` and do not install into any repository.
- One self-contained HTML page (inline CSS and JS) is preferred.
- Do not commit or push. The user reviews and commits dotfiles changes themselves.
- The user prefers dot points over prose for any list of three or more items.

## Deliverables

1. A short findings section added to the end of this file, covering:
   - each question above, with what you tried and what happened
   - a recommendation: web only, pane only, or both
   - the cost of maintaining it
2. If the recommendation includes a web page, a prototype under `~/dotfiles/claude/mods/jm-review-picker/`, or a
   skill under `~/dotfiles/claude/skills/` if it turns out not to need the mod. The prototype should take the same
   `propose_changes` input and produce the same reply text.
3. Steps the user can follow to try it, including the URL or command and what they should see.

## Findings (2026-10-23)

### Recommendation: both, with the pane as the default

The pane stays as it is and gains an **Open in browser** button. `propose_changes` takes no new arguments and both
routes send the same reply text, so review skills don't change. Choose the page for long lists or diffs that need word
highlights, and stay in the pane for short ones.

### What was built

- `server/review-server.mjs`: about 100 lines of Node standard library. It reads the parsed review as JSON on stdin,
  binds `127.0.0.1` on a port the OS picks, prints `{"url": ...}`, and then prints `{"selected": [...]}` and exits
  when the user presses Apply.
- `server/page.html`: a single self-contained page with inline CSS and JS. It has real checkboxes, an inline diff
  with word-level highlights (an LCS over word tokens; a line rewritten outright gets only the line background),
  context lines, proposals with their file lists, Tick all / Untick all, light and dark themes, and a status line
  after sending.
- `hooks/register.tsx`:
  - A `web` atom (`idle | starting | open | failed`).
  - The **Open in browser** / **Open page again** button.
  - `serve()`, which runs the server through `$.process.spawn` and reads its stdout lines.
  - `answer()`, which is now shared by the pane's Apply and the page's Apply.
  - A new `propose_changes` call, or Apply in the pane, stops any running server. `session.start` resets `web`,
    because a reload kills the child process.
- `types/index.d.ts`: adds the `Web` type.
- `hooks/register.test.tsx`: adds a test in which a stand-in for `process.spawn` prints a URL and then `[2]`. It
  checks that `$BROWSER <url>` is run, that the reply is `Apply these changes from the "Comment accuracy" review:
  2.\nSkip: 1.`, and that the pane then shows the sent state.

Checks run:

- `claude plugin validate`: passes. The only warning is the missing author field.
- `tsc` 5.6 against the engine's types: clean.
- `claude plugin test`: 4 of 4 pass.
- The server was driven with curl:
  - page 200
  - wrong token 404
  - foreign `Host` 403
  - foreign `Origin` 403
  - unknown change number 400
  - valid submit 200, prints the sorted numbers, and the process exits
- The page was driven in headless Chromium (Playwright): no console errors in either theme; untick then Apply posts
  `[1, 4]` and shows "Sent to Claude: apply 1, 4; skip 2, 3."

### 1. How the choice gets back to Claude

- **Used: the mod supervises the server.** `$.process.spawn` returns a stream of the child's output, and the child
  lives as long as the loop reading it. Ending the loop (`stream.return`), the dispatch aborting, or the module
  unloading kills the child, so a reload cannot leave an orphan. The mod reads the `selected` line and calls
  `$.prompt.submit({ text, asUser: true })` exactly as the pane does. The docs say a plugin's prompt queues and starts
  its own turn once the session is idle. Nothing polls, and no result file is written.
- **Not used: a result file with `Monitor` or a background command.** It needs a turn in progress to arm the watch,
  and it puts file-watching logic into every review skill.
- **Not used: the user says "done" and a skill reads the result over HTTP**, as diffx-review does. That costs an
  extra message and a second skill phase, for no gain over the above.
- **Not verified in a live session:** that a spawn started from a pane button press keeps running after the press
  handler returns. The reference shows this pattern for `session.start` and says a child dies only when its loop
  ends, the dispatch's signal aborts, or the module unloads. The test kit waits for the work to settle, so it cannot
  show this either way. If the page reports "Could not reach Claude Code" straight away, this is the cause. The
  fallback is to start the spawn from `session.start` and hand it reviews over a pipe.
- `$.http.fetch` combined with `$.clock.every` would also work, but it is polling and was not needed.

### 2. Opening the page automatically

- In the VS Code remote, `$BROWSER` is VS Code's `helpers/browser.sh`, which runs `code --openExternal <url>`.
  `openExternal` routes `localhost` / `127.0.0.1` URLs through VS Code's port forwarding (`asExternalUri`), so the
  server's port doesn't need forwarding by hand. The browser it lands in may use a different local port; the server
  accepts any port on `localhost` / `127.0.0.1`.
- Tried: `$BROWSER http://127.0.0.1:<port>/<token>/` from this container exited 0. The server later received a valid
  submit (`{"selected":[1,2,4]}`, different from the starting ticks) and exited. Only a browser holding the tokened
  URL could have sent that, so the tab opened, the port was forwarded with no manual step, and the page's Apply
  reached the server through the forward.
- The pane also shows the URL as a `Link` in case nothing opens. The `Link` docs say a remote surface draws
  non-`https` links as plain text, so in VS Code the URL may not be clickable. It can still be copied.
- Outside VS Code (`BROWSER` unset), nothing opens and the pane shows the URL.

#### Opening it in VS Code's Simple Browser (added later the same day)

- `code --openExternal` always opens the system browser. VS Code sends it to the workbench without
  `allowContributedOpeners`, so a `workbench.externalUriOpeners` setting that routes `localhost:*` to
  `simpleBrowser.open` is ignored for it. The same setting does apply to a link clicked in an editor tab.
- `vscode/` holds a small VS Code extension, `dusc.review-picker-browser`. It runs on the container side
  (`extensionKind: workspace`), registers a URI handler, and for
  `vscode://dusc.review-picker-browser/open?url=<page url>` it forwards the port with `asExternalUri` and runs
  `simpleBrowser.show`. It accepts only `http://127.0.0.1:<port>/` and `http://localhost:<port>/` URLs.
- `openUrl` in the mod asks the remote CLI beside `$BROWSER` (`<server>/bin/remote-cli/code --list-extensions`,
  about 0.1s). With the extension listed, it opens the `vscode://` URL through `$BROWSER`; otherwise it opens the
  page URL as before.
- VS Code may ask once whether to let the extension open the URI.
- To build and install it after a change, or in a new container:
  ```
  cd <scratch dir> && cp ~/dotfiles/claude/mods/jm-review-picker/vscode/{package.json,extension.js} .
  npx --yes @vscode/vsce@3.2.1 package --skip-license --allow-missing-repository
  "$(dirname "$BROWSER")/../remote-cli/code" --install-extension review-picker-browser-0.1.0.vsix
  ```

### 3. A browser tab compared with the pane

What the tab costs:

- It isn't visible beside the chat, so you switch windows and back.
- The reply arrives in Claude Code while you're looking at the browser.
- The ticks in the pane and on the page are independent. The page starts from the pane's ticks at the moment it was
  opened, and whichever Apply is pressed first wins.
- It depends on `node` being on `PATH` for the Claude process, and on port forwarding.

What the tab gains:

- Real checkboxes.
- Pixel layout.
- Word-level diff highlights.
- Horizontal scrolling for long lines.
- Room for long lists, with Apply always in reach in a fixed bottom bar.

### 4. Security

- The server binds `127.0.0.1` only.
- A random 128-bit token is the path prefix, so another page or process that doesn't know the URL cannot load or
  post.
- `Host` must be `localhost` or `127.0.0.1` (a guard against DNS rebinding). A non-local `Origin` is refused on every
  request.
- The page sets a CSP: script and style only by nonce, `connect-src 'self'`. Framing is allowed so VS Code's Simple Browser can show it. It also sends
  `no-store` and `no-referrer`.
- The review travels over stdin and is embedded in the page with `<` escaped. Nothing about the review goes into a
  URL, stdout, stderr or a log; stdout carries only the URL and the change numbers.
- Remaining exposure: a process running as the same user can still read the URL (for example from the pane, or by
  inspecting the process), which is the same trust boundary as the session itself.

### 5. Coexisting

Done as described: the pane is the default, the page is opt-in from a button, and the contract is unchanged.

### Maintenance cost

- About 290 new lines in total:
  - server, about 100
  - page, about 190
  - mod, about 90 more
- There are two renderers of the same `Change`. The page repeats `location()` (`place()` there) and `lines()`, so a
  new field on `Change` means editing the page too.
- There are no runtime dependencies beyond Node 22. The page isn't covered by `claude plugin test`; it was checked
  with Playwright by hand.
- Possible next steps, none built:
  - a `userConfig` option to open the page automatically on every `propose_changes`
  - keeping the pane's and the page's ticks in sync over `$.http.fetch`

### Try it

The mod reloads by itself when a session saves files in its folder; otherwise start a new session.

1. Run `/jm-review` (or any review) so the Review pane opens. The pane looks as it did before, with a new **Open in
   browser** button after Untick all.
2. Press **Open in browser**. A browser tab should open at `http://127.0.0.1:<port>/<token>/`, or at a forwarded
   `localhost` port. The pane gains a line reading `Page: <url>`.
3. Untick a change on the page and press **Apply selected (n)**. The page says "Sent to Claude: apply …; skip ….
   You can close this tab." In Claude Code the pane switches to its sent state, and a prompt in the usual form
   arrives, e.g. `Apply these changes from the "Comment accuracy" review: 1, 3.` / `Skip: 2.`
4. If no tab opens, copy the URL from the pane. If the page says it cannot reach Claude Code straight after opening,
   see the "Not verified" point under question 1.
