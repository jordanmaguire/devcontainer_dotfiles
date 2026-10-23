---
name: jm-review
description: Run one or more of the user's own code reviews (comment accuracy, and others listed in this skill's reviews/ folder) over the current branch, staged changes or a path, and let the user tick which suggestions to apply in the review-picker pane. Triggers on "/jm-review", "run my reviews", "review the comments on this branch", "do a comment review", or any named review in reviews/. Not for a correctness bug hunt (that is /code-review).
argument-hint: "[review names...] [staged | working | <path> | <git range>]"
---

# jm-review

Each file in `reviews/` (next to this file) is one review: what to look for, what to leave alone, and the shape its
suggestions take. This skill picks the scope and the reviews, runs them one at a time, and hands each review's
suggestions to the user to tick in the `review-picker` pane.

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
3. Draft the suggestions in the shape the review file asks for:
   - **Edit**: `file` (repo-relative), `line`, `before`, `after`, `reason`, and `context_after` when the line below
     helps (the method a comment sits on). `before` must be the current text, verbatim with indentation. Read the
     file at that line to confirm it before sending.
   - **Proposal**: `proposal` (what to change, a few sentences or a dash list), `files`, `reason`. Use it only for
     changes too broad for one text replacement.
4. Drop anything the review file says to leave alone, and anything you would not defend if asked. Fewer, sound
   suggestions beat a long list.
5. If nothing survives, say "<review>: nothing to suggest" with one line on what was checked, and move on to the
   next review in the same turn.
6. Otherwise call `mcp__review-picker__propose_changes` with the review's `name` as `title` and the suggestions in
   file order. Then end the turn with one line: the review shown, how many suggestions, and which reviews are
   still to run. Do not list the suggestions in chat; the pane shows them.

If `mcp__review-picker__propose_changes` is not available, fall back to `AskUserQuestion`: one question per
suggestion, options "Apply" and "Skip", the `preview` of "Apply" showing the old and new text. Four suggestions per
call; make several calls for more.

## 4. Act on the user's choice

The pane replies with a message such as:

```
Apply these changes from the "Comment accuracy" review: 1, 3, 4.
Skip: 2.
```

- **Edits**: apply each ticked one with `Edit`, `before` as `old_string`. If `before` no longer matches (the file
  changed), re-read it, apply the same intent if it still holds, and say so.
- **Proposals**: carry out each ticked one. If a proposal would touch more than about 5 files or change behaviour,
  give a short plan first and wait for a go-ahead.
- Run the narrowest check that covers what changed: a syntax check for comment-only edits (`ruby -c`, the
  project's equivalent), the related specs for proposals. Follow the project's CLAUDE.md for how to run them.
- Report in one or two lines what was applied and what was skipped, then start the next review. After the last
  review, summarise each review's applied and skipped counts.

Never commit. When everything is applied and the scope was the branch, offer `/git-fixup` to fold the edits into
the commits they belong to.

## Adding a review

A review is a Markdown file in `reviews/`, named after the review, with this front matter:

```yaml
---
name: Comment accuracy          # the pane title and how the user names it
description: One line, shown in the picker
suggests: edits                 # edits, proposals, or both
---
```

and these sections:

- **Look for**: what to flag, most important first.
- **Leave alone**: what not to flag, so the list stays short.
- **Format**: house rules the new text must follow.
- **Example**: one before and after.
