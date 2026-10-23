// An exact text replacement, drawn as a diff.
export type Edit = {
  kind: 'edit'
  id: number
  file: string
  line: number
  reason: string
  before: string
  after: string
  contextAfter: string
  isSelected: boolean
}

// A change too broad for one replacement (extract a class, move a method), drawn as a description.
export type Suggestion = {
  kind: 'proposal'
  id: number
  files: string[]
  reason: string
  proposal: string
  isSelected: boolean
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
    'review-picker': { proposal: Proposal; web: Web }
  }
}
