---
name: git-fixup
description: Use when the user wants to turn their current working-tree changes into a `git commit --fixup` against the right commit on the current branch. Triggers on phrases like "fixup this", "make a fixup commit", "fixup these changes", "/git-fixup". The skill identifies which branch commit each modified file belongs to (via line-level blame), creates one fixup commit per target, and reports if no suitable target can be found.
---

# git-fixup

Turn the user's current working-tree changes into one or more `git commit --fixup=<sha>` commits, each targeting the branch commit that the change logically belongs to. The user will rebase with `--autosquash` afterwards.

## Operating principles

- **One fixup per target commit.** If different changed files map to different branch commits, create one fixup commit per target — stage only the matching files for each.
- **Scope = everything modified.** Include both staged and unstaged changes. Untracked files are excluded (a brand-new file has nothing to fix up).
- **Target selection = best hunk overlap.** For each file, blame the lines being modified and pick the branch commit that last touched the most of those lines. Fall back to "most recent branch commit that touched the file" only if blame is inconclusive.
- **Never guess past the branch boundary.** Only commits between the merge-base with the default branch and `HEAD` are eligible targets. If a file's changes all blame to commits outside that range (i.e., on the base branch), do not invent a target — report and stop for that file.
- **Don't touch history.** This skill only creates new commits. It never rebases, amends, resets, or force-pushes. The user runs the autosquash themselves.

## Procedure

### 1. Sanity checks

- Confirm `git status` shows at least one modified or staged tracked file. If only untracked files exist, report and stop.
- Determine the branch base:
  - Try `git symbolic-ref refs/remotes/origin/HEAD` → default branch.
  - Fall back to `master`, then `main`.
  - Compute `BASE=$(git merge-base HEAD <default-branch>)`.
- Collect the eligible target SHAs: `git log --format=%H "$BASE"..HEAD`. If this list is empty, the branch has no commits of its own — report and stop.

### 2. For each modified tracked file, pick a target commit

For each file in `git diff --name-only HEAD` (covers staged + unstaged together):

1. Get the pre-image hunk ranges from `git diff -U0 HEAD -- <file>`. Each `@@ -X,Y +... @@` contributes the line range `X..X+Y-1` (when `Y` is `0`, use a 1-line window around `X` to capture the insertion context).
2. For each range, run `git blame -l --root HEAD -L <start>,<end> -- <file>` and collect the commit SHA per line.
3. Filter the SHAs to those in the `BASE..HEAD` set from step 1.
4. Tally by SHA. The SHA with the most lines wins. On a tie, prefer the more recent commit (later in `git log "$BASE"..HEAD`).
5. If no lines blame to any in-range commit:
   - Fall back to `git log "$BASE"..HEAD --format=%H -- <file>` and take the most recent.
   - If that is also empty, mark the file as **no target** and continue with the others.

### 3. Group files by target SHA

Build a mapping `target_sha -> [files...]`. Files marked **no target** go in a separate "unmatched" bucket.

### 4. Show the plan, then act

Before committing, print a short plan:

```
Fixup plan:
  <short-sha> <subject>
    - path/to/file_a
    - path/to/file_b
  <short-sha> <subject>
    - path/to/file_c

Unmatched (no fixup created):
  - path/to/file_d  (reason: only blames to commits on <default-branch>)
```

Then, for each `target_sha -> files` entry:

1. `git reset` once at the start so the index is clean (only do this if mixed staged/unstaged state would otherwise lump everything together). If everything is already in one bucket, skip the reset.
2. `git add -- <files>` for that group.
3. `git commit --fixup=<target_sha> --no-verify=false` — i.e., run hooks normally, don't bypass them.
4. Capture the new commit SHA for the final report.

If any commit fails (e.g., a pre-commit hook), stop immediately. Do not retry with `--no-verify`. Report what failed and leave the index as-is so the user can inspect.

### 5. Report

End with a concise summary:

```
Created N fixup commit(s):
  <new-sha> fixup! <subject>     -> targets <short-sha>
  ...

Unmatched files (no commit created): <list or "none">

Next step: git rebase -i --autosquash <BASE>
```

## When to stop and report instead of acting

Report back without creating any commit if **any** of these are true:

- No tracked changes exist (only untracked files, or nothing at all).
- The branch has no commits of its own (`BASE..HEAD` is empty).
- Every changed file falls into the "unmatched" bucket.
- You are uncertain about the target for a file and the user has not invoked this skill with explicit "just pick something" intent. When in doubt, list candidates and let the user choose.

## Things to avoid

- Do not run `git rebase`, `git commit --amend`, `git reset --hard`, or `git push` as part of this skill.
- Do not bypass hooks with `--no-verify`.
- Do not stage untracked files. New files are out of scope.
- Do not create an empty fixup commit. If a target bucket ends up with zero stageable changes after `git add`, skip it and note why.
- Do not edit the commit message produced by `--fixup`; Git generates `fixup! <original subject>` and autosquash relies on that exact form.
