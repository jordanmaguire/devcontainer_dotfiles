---
name: jm-review
description: Run one or more of the user's own code reviews (comment accuracy, and others listed in this skill's reviews/ folder) over the current branch, staged changes or a path, let the user tick which suggestions to apply on the jm-review-picker page, then commit the applied ones as fixups or new commits. Triggers on "/jm-review", "run my reviews", "review the comments on this branch", "do a comment review", or any named review in reviews/. Not for a correctness bug hunt (that is /code-review).
argument-hint: "[review names...] [staged | working | <path> | <git range>]"
---

# jm-review

Each file in `reviews/` (next to this file) is one review: what to look for, what to leave alone, and the shape its
suggestions take. This skill picks the scope and the reviews, runs them one at a time, and hands each review's
suggestions to the user to tick on the `jm-review-picker` page, each labelled with the commit it will go into. The
ticked ones are applied and committed as the page showed.

## 1. Work out the scope

Read the arguments. Anything that is not a review name is the scope.

| Argument | Scope | Diff to read |
|----------|-------|--------------|
| none | the branch, committed and uncommitted | `git diff $(git merge-base HEAD <default>)` |
| `staged` | the index | `git diff --cached` |
| `working` | uncommitted changes | `git diff HEAD` |
| a path | that file or folder as it stands, whole | read the files; there is no diff |
| a git range (`a..b`) | that range | `git diff a..b` |

`<default>` is the branch `git symbolic-ref refs/remotes/origin/HEAD` names, else `master`, else `main`. With
a diff scope, include untracked files the branch adds (`git ls-files --others --exclude-standard`) and read them
whole. If the scope holds no changes, say so and stop.

A review only comments on lines the scope adds or changes, unless its file says otherwise. Code the branch did not
touch is out of bounds, even when it has the same problem.

## 2. Pick the reviews

List the reviews: each `reviews/*.md` file, by the `name` and `description` in its front matter.

- If the arguments name reviews (by file name, `name`, or an obvious short form such as "comments"), run those.
- Otherwise ask with `AskUserQuestion`, `multiSelect: true`. A question takes at most 4 options, so with more than 4
  reviews split them across questions (up to 4 questions). Describe each option with its `description`.
- If only one review exists, run it without asking.

Say which reviews will run, in order, in one line.

## 3. Run each review in turn

Run the reviews one after another, not all at once. Each one reads the code as the user's choices from the
previous review left it, so two reviews never suggest conflicting changes to the same lines.

For each review:

1. Read its file in full and follow it. Its rules beat any general taste.
2. Collect candidates from the scope. For a large scope (more than about 15 files), hand the search to an `Explore`
   or `general-purpose` subagent with the review file's text and the file list, and ask for candidates as
   `file:line` with the current text. Keep the judgement of what to suggest in the main conversation.
3. Draft the suggestions in the shape the review file asks for. Every suggestion has a `title`: a few words saying
   what it does ("Say what membership returns", "Move CSV building out of the controller"), never a file name;
   the card shows the file under it.
   - **Edit**: `file` (repo-relative), `line`, `before`, `after`, `reason`, and `context_after` when the line below
     helps (the method a comment sits on). `before` must be the current text, verbatim with indentation. Read the
     file at that line to confirm it before sending.
   - **Proposal**: `proposal` (what to change, a few sentences or a dash list), `files`, `reason`. Use it only for
     changes too broad for one text replacement.
4. Drop anything the review file says to leave alone, and anything you would not defend if asked. Fewer, sound
   suggestions beat a long list.
5. Give each surviving suggestion its `commit`, as **Choosing the commit** below says.
6. If nothing survives, say "<review>: nothing to suggest" with one line on what was checked, and move on to the
   next review in the same turn.
7. Otherwise call `mcp__jm-review-picker__propose_changes` with the review's `name` as `title` and the suggestions in
   file order. Then end the turn with one line: the review shown, how many suggestions, and which reviews are
   still to run. Do not list the suggestions in chat; the page shows them.

If `mcp__jm-review-picker__propose_changes` is not available, fall back to `AskUserQuestion`: one question per
suggestion, options "Apply" and "Skip", the `preview` of "Apply" showing the old and new text and the commit. Four
suggestions per call; make several calls for more.

### Choosing the commit

The page shows each change's commit beside its title, so the user can approve the lot at once.
Work it out the way `/git-fixup` does, but per change rather than per file.

- `BASE` is the merge-base with the default branch from step 1. Only commits in `BASE..HEAD` can be fixed up.
- **Edit**: blame the lines it replaces in the working tree, `git blame -l -L <line>,+<lines in before> -- <file>`
  (for a pure insertion, the `context_after` line). Then:
  - Most lines from commits in `BASE..HEAD`: `commit: { fixup: <that sha> }`. On a tie, the more recent commit.
    A `fixup!` commit is fine to name; the picker maps it to the commit it fixes.
  - Most lines from commits before `BASE`: `commit: { message }`, a new commit.
  - Lines blamed to `0000000` (uncommitted work): leave `commit` out. The change stays uncommitted with that work.
- **Proposal**: a fixup when it reshapes code one branch commit added and belongs in that commit's story; else a
  new commit. Leave `commit` out if any file it touches has uncommitted changes (`git status --porcelain -- <files>`),
  since the commit could not hold the proposal alone.
- **Messages**: follow the repository's style (`git log --format=%s -20`). Name what changes and why, never the
  review, Claude or AI. New-commit suggestions on one theme share one message word for word, so they share a commit.
- With a path scope outside a git repository, or nothing in `BASE..HEAD` and no reason for a new commit, leave
  `commit` out everywhere.

## 4. Act on the user's choice

The page (or pane) replies with a message such as:

```
Apply these changes from the "Comment accuracy" review: 1, 3, 4.
Skip: 2.

My notes on these changes; answer each one, and where a note asks for something else, do that:
- 2: Keep it: the counter is not obvious
```

The notes block appears only when the user wrote one.

- **Notes**: answer every note in the report, ticked or skipped. A note that asks for something other than the
  suggestion (different wording, a wider fix) replaces the suggestion; a question is answered before acting on the
  change it is on, and if the answer would change the edit, ask before applying it.
- **Notes that change the plan**: a note asking for a different commit ("its own commit", "fold into abc1234")
  moves the change there. A note that changes an edit's text keeps its commit.

Then make the commits the page showed, one group at a time, in the order the changes are numbered. A group is the
ticked changes sharing a `commit`.

- **Edits with a commit**: send the group to `scripts/commit-edits.mjs` (next to this file). It makes the edits in
  the working tree and the index and commits the index alone, so other uncommitted work in those files stays out.
  Do not also `Edit` these changes; the script makes them. Run it from the repository, with the JSON quoted:

  ```bash
  node <this skill's folder>/scripts/commit-edits.mjs <<'JSON'
  {"fixup": "<full sha>", "edits": [{"file": "app/models/user.rb", "line": 10, "before": "...", "after": "...", "context_after": "..."}]}
  JSON
  ```

  For a new commit, give `"message": "<subject>\n\n<body>"` instead of `fixup`. `--check` works a group out
  without writing anything.
- **Proposals with a commit**: carry each one out with `Edit` and `Write`, then `git add -- <its files>` and
  `git commit --fixup=<sha>` (or `git commit -F -` with the message). A group holding both edits and proposals
  becomes two commits with the same target: the edits through the script first, then the proposals. If a proposal
  would touch more than about 5 files or change behaviour, give a short plan first and wait for a go-ahead.
- **Changes without a commit**: apply with `Edit`, `before` as `old_string`. If `before` no longer matches (the
  file changed), re-read it, apply the same intent if it still holds, and say so.
- **When the script refuses a group**, it has written nothing. If the reason is something already staged, stop and
  ask the user. Otherwise apply that group with `Edit`, leave it uncommitted, and say why.

Run the narrowest check that covers what changed: a syntax check for comment-only edits (`ruby -c`, the project's
equivalent), the related specs for proposals. Follow the project's CLAUDE.md for how to run them. If a check fails,
say so and fix it in the working tree; do not amend a commit.

Report the commits made (short sha and subject), what stayed uncommitted and why, and what was skipped, then start
the next review. After the last review, summarise each review's counts and give the next step:
`git rebase -i --autosquash <BASE>`.

Never rebase, amend, reset a commit, push, or pass `--no-verify`.

## Adding a review

A review is a Markdown file in `reviews/`, named after the review, with this front matter:

```yaml
---
name: Comment accuracy          # the page title and how the user names it
description: One line, shown in the picker
suggests: edits                 # edits, proposals, or both
---
```

and these sections:

- **Look for**: what to flag, most important first.
- **Leave alone**: what not to flag, so the list stays short.
- **Format**: house rules the new text must follow.
- **Example**: one before and after.
