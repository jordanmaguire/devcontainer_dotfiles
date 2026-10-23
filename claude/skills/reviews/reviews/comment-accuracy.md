---
name: Comment accuracy
description: Make the comments the scope adds direct and literal, cut the unnecessary ones, and list enumerations
suggests: edits
---

# Comment accuracy

Only comments the scope adds or changes. A comment the branch did not touch is out of bounds.

## Look for

- **Comments that are not needed.** Suggest deleting (`after` empty) a comment that:
  - restates what the next line of code plainly does
  - repeats another comment nearby (e.g. a method comment repeating the class comment)
  - argues a point a spec already pins; the spec is the record
- **Comments that could be shorter.** Cut clauses that add nothing the reader needs to work on the code: history the
  commit message already holds, asides, a second wording of the same point.
- **Indirect or figurative wording.** Say what the code does in plain terms.
  - "Both halves of the stored location" → "Writes and reads the stored location".
  - Hedges ("more likely", "should probably", "it seems") → state what is known, or cut the claim.
  - A vague subject ("the check", "it", "this") → name the variable, method or value.
- **Steps out of order.** Describe what happens in the order it happens.
- **Enumerations in prose.** Three or more parallel items (steps, cases, reasons, method names), or two long ones,
  belong in a list; see Format.
- **Lists whose items do not follow from their heading.** Either reword the heading or split the comment.
- **Facts that will go stale.** Paths to spec files and line numbers in comments drift; drop them unless the
  comment exists to point there.

## Leave alone

- Comments that explain why: a constraint, a past incident, a limit (a cookie size, an API quirk). Tighten them,
  never delete them.
- Precise numbers and identifiers (byte counts, fault IDs, dates). They are why the comment exists.
- `# Override: <Module>` markers and other house conventions already in the file.
- Wording that is a matter of taste only. If the new text is not shorter, clearer or more literal, do not suggest
  it.
- Code. This review changes comments only.

## Format

- Wrap at the file's line length (120 in the `iex` repo). Keep the comment's indentation.
- Lists use dashes, indented two spaces after the comment marker, with continuation lines aligned under the item's
  text:

  ```ruby
  # My cool comment with items:
  #   - First. This has some additional text that when wrapped
  #     will indent inline with the dot point it will visually group them
  #   - Second. This is on one line.
  ```

- Number the items instead only when their order matters (steps).
- End each item with a full stop when items are sentences; leave bare identifiers bare (`- challenge_succeeded!`).
- Separate paragraphs in one comment with an empty comment line (`#`).

## Example

Before:

```ruby
  # Call only after the step that clears the circuit breaker (challenge_succeeded!, *_configuration_succeeded!,
  # mfa_optional_users_prompt_shown) has been saved. Before it, after_sign_in_path_for returns the MFA page the user
  # is already on.
```

After:

```ruby
  # Call only after the step that clears the circuit breaker has been saved:
  #   - challenge_succeeded!
  #   - *_configuration_succeeded!
  #   - mfa_optional_users_prompt_shown
  # Before it, after_sign_in_path_for returns the MFA page the user is already on.
```

Reason given: the three steps are an enumeration buried in parentheses; a dash list makes them scannable.
