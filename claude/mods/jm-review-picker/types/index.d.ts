// The commit a change goes into once applied: a fixup of a commit on this branch, a new commit with its message, or
// none (the change stays in the working tree).
export type Commit =
  | { kind: 'fixup'; sha: string; short: string; subject: string }
  | { kind: 'new'; message: string }
  | { kind: 'none' }

// What every change carries besides its content: a readable title, the commit it goes into, the user's tick, whether
// its card is expanded, and their note.
export type Common = {
  id: number
  title: string
  reason: string
  commit: Commit
  isSelected: boolean
  isOpen: boolean
  // What the user wrote about this change for Claude to answer, '' when nothing.
  note: string
}

// An exact text replacement, drawn as a diff.
export type Edit = Common & {
  kind: 'edit'
  file: string
  line: number
  before: string
  after: string
  contextAfter: string
}

// A change too broad for one replacement (extract a class, move a method), drawn as a description.
export type Suggestion = Common & {
  kind: 'proposal'
  files: string[]
  proposal: string
}

export type Change = Edit | Suggestion

export type Proposal = {
  title: string
  changes: Change[]
  status: 'empty' | 'open' | 'sent'
}

// The local web page that shows the same review: not started, starting, serving at `url`, or failed to start.
export type Web =
  | { status: 'idle' }
  | { status: 'starting' }
  | { status: 'open'; url: string }
  | { status: 'failed'; reason: string }

declare module 'claude-code' {
  interface PluginState {
    'jm-review-picker': { proposal: Proposal; web: Web }
  }
}
