import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Change, Commit, Edit, Proposal, Web } from '../types'

const PANE = 'jm-review-picker'
const TOOL = 'propose_changes'
const EMPTY: Proposal = { title: '', changes: [], status: 'empty' }
const proposal = atom({ plugin: 'jm-review-picker', key: 'proposal' } as const, EMPTY)
const IDLE: Web = { status: 'idle' }
const web = atom({ plugin: 'jm-review-picker', key: 'web' } as const, IDLE)

// The running web page server, if any. It dies with the module, so a reload starts with none.
let server: { stop: () => void } | undefined

const DESCRIPTION = [
  'Show a numbered list of suggested changes on a web page in the user\'s browser (or a side pane',
  'when no browser can be opened), where the user ticks which ones to carry out. Use it whenever a',
  'review produces suggestions for the user to accept or reject.',
  '',
  'Each change has a short readable `title` (what it does, not where) and is one of:',
  '  - An edit: an exact text replacement (`file`, `line`, `before`, `after`), drawn as a diff.',
  '  - A proposal: a change too broad for one replacement, such as extracting a class or moving',
  '    a method (`proposal`, and the `files` it touches), drawn as a description.',
  '',
  'Each change can name the commit it goes into once applied (`commit`): `{ "fixup": "<sha>" }` for',
  'a commit on this branch, or `{ "message": "<subject>\\n\\n<body>" }` for a new commit; changes with',
  'the same message share it. Leave `commit` out for a change that stays uncommitted. The page shows',
  'this plan to the user, so commit exactly as it says.',
  '',
  'After calling it, end your turn without repeating the list in chat. The user answers with a',
  'message naming the change numbers to apply and to skip; carry out only those. Numbers follow',
  'the order of `changes`, starting at 1. Calling again replaces the list in the pane.',
  '',
  'The user can write a note on any change, ticked or not. Notes follow the numbers in the reply:',
  'answer each one, and where a note asks for something other than the suggestion, do that instead.',
].join('\n')

const SCHEMA = {
  type: 'object',
  required: ['title', 'changes'],
  properties: {
    title: {
      type: 'string',
      description: 'Name of the review, e.g. "Comment accuracy"',
    },
    changes: {
      type: 'array',
      minItems: 1,
      items: {
        type: 'object',
        required: ['title', 'reason'],
        properties: {
          title: {
            type: 'string',
            description:
              'A few words a person can read at a glance saying what the change does, e.g. "Say what membership returns". Not a file name.',
          },
          reason: {
            type: 'string',
            description: 'One short sentence on why the change helps',
          },
          commit: {
            type: 'object',
            description:
              'The commit the change goes into once applied: `fixup` or `message`, not both. Leave out to keep the change uncommitted.',
            properties: {
              fixup: {
                type: 'string',
                description: 'Sha (full or at least 7 characters) of the commit on this branch that the change fixes up',
              },
              message: {
                type: 'string',
                description: 'Message of a new commit: subject, blank line, body. Changes with the same message share the commit.',
              },
            },
          },
          file: { type: 'string', description: 'Edit: repo-relative path' },
          line: {
            type: 'integer',
            minimum: 1,
            description: 'Edit: line number where `before` starts in the current file',
          },
          before: {
            type: 'string',
            description: 'Edit: the current lines, verbatim with indentation. Empty when only adding lines.',
          },
          after: {
            type: 'string',
            description: 'Edit: the replacement lines, verbatim with indentation. Empty to delete `before`.',
          },
          context_after: {
            type: 'string',
            description:
              'Edit, optional: the unchanged line(s) right after `before`, e.g. the method a comment sits on, shown for orientation',
          },
          proposal: {
            type: 'string',
            description:
              'Proposal: what to change, in a few plain sentences or a dash list. Give this instead of the edit fields.',
          },
          files: {
            type: 'array',
            items: { type: 'string' },
            description: 'Proposal: repo-relative paths the change touches',
          },
        },
      },
    },
  },
}

const lines = (text: string): string[] =>
  text === '' ? [] : text.replace(/\r/g, '').replace(/\n$/, '').split('\n')

type DiffLine = { kind: 'removed' | 'added' | 'context'; text: string }

// Drawn as Text lines with the theme's diff backgrounds rather than a Code diff, so the colours do not depend on how
// each surface draws Code.
const diffLines = (change: Edit): DiffLine[] => [
  ...lines(change.before).map(text => ({ kind: 'removed' as const, text: `- ${text}` })),
  ...lines(change.after).map(text => ({ kind: 'added' as const, text: `+ ${text}` })),
  ...lines(change.contextAfter).map(text => ({ kind: 'context' as const, text: `  ${text}` })),
]

const DIFF_BACKGROUND = { removed: 'diffRemoved', added: 'diffAdded', context: undefined } as const

const checkbox = (change: Change): string => (change.isSelected ? '☑' : '☐')

// Where the change lands: the edit's file and line, or each file a proposal touches.
const places = (change: Change): string[] => (change.kind === 'edit' ? [`${change.file}:${change.line}`] : change.files)

const subjectOf = (message: string): string => lines(message.trim())[0] ?? ''

const commitLabel = (commit: Commit): string => {
  if (commit.kind === 'fixup') return `fixup! ${commit.subject} (${commit.short})`
  if (commit.kind === 'new') return `New commit: ${subjectOf(commit.message)}`

  return 'Not committed'
}

// Changes with the same key go into the same commit.
const commitKey = (commit: Commit): string => {
  if (commit.kind === 'fixup') return `fixup:${commit.sha}`
  if (commit.kind === 'new') return `new:${commit.message.trim()}`

  return 'none'
}

const hasCommits = (changes: Change[]) => changes.some(change => change.commit.kind !== 'none')

// The fixup's sha is checked against the branch later, by resolveCommits; until then `sha` holds what Claude gave.
const parseCommit = (raw: unknown, at: string): Commit | string => {
  if (raw === undefined) return { kind: 'none' }
  const { fixup, message } = (raw ?? {}) as Record<string, unknown>
  if (fixup !== undefined && message !== undefined) return `${at}.commit takes \`fixup\` or \`message\`, not both.`
  if (fixup !== undefined) {
    if (typeof fixup !== 'string' || !/^[0-9a-f]{7,40}$/i.test(fixup.trim()))
      return `${at}.commit.fixup must be a commit sha of at least 7 characters.`

    return { kind: 'fixup', sha: fixup.trim().toLowerCase(), short: '', subject: '' }
  }
  if (typeof message !== 'string' || message.trim() === '')
    return `${at}.commit needs \`fixup\` or a non-empty \`message\`; leave \`commit\` out to keep the change uncommitted.`

  return { kind: 'new', message: message.trim() }
}

const parseChange = (raw: unknown, index: number): Change | string => {
  const item = (raw ?? {}) as Record<string, unknown>
  const { title, file, line, reason, before, after, context_after, proposal: text, files } = item
  const at = `changes[${index}]`
  if (typeof title !== 'string' || title.trim() === '') return `${at}.title must be a non-empty string.`
  if (typeof reason !== 'string') return `${at}.reason must be a string.`
  const commit = parseCommit(item.commit, at)
  if (typeof commit === 'string') return commit
  const common = { id: index + 1, title: title.trim(), reason, commit, isSelected: true, isOpen: true, note: '' }

  if (text !== undefined) {
    if (typeof text !== 'string' || text.trim() === '') return `${at}.proposal must be a non-empty string.`
    if (files !== undefined && !(Array.isArray(files) && files.every(path => typeof path === 'string')))
      return `${at}.files must be an array of paths when given.`

    return { ...common, kind: 'proposal', proposal: text.trim(), files: (files as string[]) ?? [] }
  }

  if (typeof file !== 'string' || file === '') return `${at} needs either \`proposal\` or the edit fields; file is missing.`
  if (typeof line !== 'number' || !Number.isInteger(line) || line < 1) return `${at}.line must be a positive integer.`
  if (typeof before !== 'string' || typeof after !== 'string') return `${at}.before and ${at}.after must be strings.`
  if (before === after) return `${at} changes nothing: before and after are the same.`
  if (context_after !== undefined && typeof context_after !== 'string')
    return `${at}.context_after must be a string when given.`

  return { ...common, kind: 'edit', file, line, before, after, contextAfter: context_after ?? '' }
}

const parse = (input: Record<string, unknown>): Proposal | string => {
  const { title, changes } = input
  if (typeof title !== 'string' || title.trim() === '') return '`title` must be a non-empty string.'
  if (!Array.isArray(changes) || changes.length === 0) return '`changes` must be a non-empty array.'

  const parsed: Change[] = []
  for (const [index, raw] of changes.entries()) {
    const change = parseChange(raw, index)
    if (typeof change === 'string') return change
    parsed.push(change)
  }

  return { title: title.trim(), changes: parsed, status: 'open' }
}

type BranchCommit = { sha: string; short: string; subject: string }

const git = async ($: EngineInterface, ...args: string[]) => {
  const run = await $.process.run(['git', ...args], { timeoutMs: 10_000 }).catch(() => undefined)

  return run?.exitCode === 0 ? run.stdout.trim() : undefined
}

// The commits the branch adds over the default branch (origin's HEAD, else master, else main), as /git-fixup finds
// them.
const branchCommits = async ($: EngineInterface): Promise<BranchCommit[] | string> => {
  const remote = await git($, 'symbolic-ref', '--quiet', '--short', 'refs/remotes/origin/HEAD')
  let base: string | undefined
  for (const name of [remote, 'master', 'main']) {
    if (name === undefined || name === '') continue
    base = await git($, 'merge-base', 'HEAD', name)
    if (base !== undefined) break
  }
  if (base === undefined) return 'no origin/HEAD, master or main to find the branch base from'
  const log = await git($, 'log', '--format=%H%x00%h%x00%s', `${base}..HEAD`)
  if (log === undefined) return 'git log failed'

  return lines(log).map(line => {
    const [sha = '', short = '', subject = ''] = line.split('\0')

    return { sha, short, subject }
  })
}

const FIXUP_PREFIX = /^(fixup! )+/

// A fixup of a fixup belongs to the commit they both fix, which is what autosquash folds them into.
const original = (commits: BranchCommit[], commit: BranchCommit): BranchCommit => {
  if (!FIXUP_PREFIX.test(commit.subject)) return commit
  const subject = commit.subject.replace(FIXUP_PREFIX, '')

  return commits.find(other => other.subject === subject) ?? commit
}

// Checks each fixup names one commit on this branch, and fills in its full sha and subject for the plan.
const resolveCommits = async ($: EngineInterface, current: Proposal): Promise<Proposal | string> => {
  if (!current.changes.some(change => change.commit.kind === 'fixup')) return current
  const commits = await branchCommits($)
  if (typeof commits === 'string') return `The fixup targets could not be checked: ${commits}.`

  const changes: Change[] = []
  for (const change of current.changes) {
    if (change.commit.kind !== 'fixup') {
      changes.push(change)
      continue
    }
    const ref = change.commit.sha
    const found = commits.filter(commit => commit.sha.startsWith(ref))
    const target = found[0]
    if (target === undefined || found.length > 1)
      return (
        `changes[${change.id - 1}].commit.fixup ${ref} is ${found.length > 1 ? 'ambiguous' : 'not a commit on this branch'}; ` +
        'fix up only a commit between the merge-base and HEAD, or give a `message` for a new commit.'
      )
    changes.push({ ...change, commit: { kind: 'fixup', ...original(commits, target) } })
  }

  return { ...current, changes }
}

const numbers = (changes: Change[]): string =>
  changes.length === 0 ? 'none' : changes.map(change => change.id).join(', ')

const selection = (current: Proposal) => {
  const chosen = current.changes.filter(change => change.isSelected)
  const skipped = current.changes.filter(change => !change.isSelected)

  return { chosen, skipped }
}

// One dash item per noted change, a note's later lines indented beneath its first.
const notes = (changes: Change[]): string[] =>
  changes
    .filter(change => change.note.trim() !== '')
    .map(change => `- ${change.id}: ${lines(change.note.trim()).join('\n  ')}`)

const message = (current: Proposal): string => {
  const { chosen, skipped } = selection(current)
  const noted = notes(current.changes)
  const tail =
    noted.length === 0
      ? []
      : ['', 'My notes on these changes; answer each one, and where a note asks for something else, do that:', ...noted]

  if (chosen.length === 0) {
    const edits = noted.length === 0 ? 'Make no edits.' : 'Make no edits beyond what a note asks for.'

    return [`Skip every change from the "${current.title}" review (${numbers(skipped)}). ${edits}`, ...tail].join('\n')
  }

  return [
    `Apply these changes from the "${current.title}" review: ${numbers(chosen)}.`,
    `Skip: ${numbers(skipped)}.`,
    ...tail,
  ].join('\n')
}

const stopServer = async ($: EngineInterface) => {
  server?.stop()
  server = undefined
  await update($, web, () => IDLE)
}

// Sends the reply exactly as the pane's Apply button does, once per review.
const answer = async ($: EngineInterface, current: Proposal) => {
  const now = await read($, proposal)
  if (now.status !== 'open') return
  await update($, proposal, () => ({ ...current, status: 'sent' as const }))
  await $.prompt.submit({ text: message(current), asUser: true })
}

// The VS Code extension in vscode/, which opens a page in VS Code's Simple Browser.
const EXTENSION = 'dusc.review-picker-browser'

// VS Code's remote CLI sits beside its $BROWSER helper: <server>/bin/helpers/browser.sh and <server>/bin/remote-cli/code.
const hasExtension = async ($: EngineInterface, browser: string) => {
  const cli = browser.replace(/\/helpers\/browser\.sh$/, '/remote-cli/code')
  if (cli === browser) return false
  const listed = await $.process.run([cli, '--list-extensions'], { timeoutMs: 10_000 }).catch(() => undefined)

  return listed?.exitCode === 0 && listed.stdout.split('\n').includes(EXTENSION)
}

// In VS Code, $BROWSER is its helper that opens the URL on the user's machine and forwards the port, always in the
// system browser. With the extension installed the URL goes to it instead, and opens in VS Code.
const openUrl = async ($: EngineInterface, url: string) => {
  const browser = await $.env.get('BROWSER')
  if (browser === undefined) return
  const target = (await hasExtension($, browser)) ? `vscode://${EXTENSION}/open?url=${encodeURIComponent(url)}` : url
  await $.process.run([browser, target], { timeoutMs: 10_000 }).catch(() => undefined)
}

// What the page draws for each change: the change, plus where it lands and its commit worked out here so the page
// does not repeat that logic.
const pageChange = (change: Change) => ({
  ...change,
  places: places(change),
  commitLabel: commitLabel(change.commit),
  commitKey: commitKey(change.commit),
})

type ServerLine = { url?: string; selected?: number[]; notes?: Record<string, string> }

// Serves the review on 127.0.0.1 from server/review-server.mjs, which prints its URL once listening and the ticked
// numbers and notes when the user presses Apply on the page. Resolves true once the page is open, or false if the
// server ended before printing a URL; the server runs on until the user applies or the module reloads.
const serve = ($: EngineInterface, current: Proposal) =>
  new Promise<boolean>(resolve => {
    const stream = $.process.spawn({
      argv: ['node', `${$.plugin.root}/server/review-server.mjs`],
      input: JSON.stringify({
        title: current.title,
        hasCommits: hasCommits(current.changes),
        changes: current.changes.map(pageChange),
      }),
    })
    const run = { stop: () => void stream.return({ code: null, signal: null }) }
    server = run

    const handle = async (line: ServerLine) => {
      if (server !== run) return
      if (line.url !== undefined) {
        await update($, web, () => ({ status: 'open' as const, url: line.url as string }))
        await openUrl($, line.url)
        resolve(true)
      }
      if (line.selected !== undefined) {
        const ticked = new Set(line.selected)
        const written = line.notes ?? {}
        const latest = await read($, proposal)
        await answer($, {
          ...latest,
          changes: latest.changes.map(change => ({
            ...change,
            isSelected: ticked.has(change.id),
            isOpen: ticked.has(change.id),
            note: written[change.id] ?? '',
          })),
        })
      }
    }

    void (async () => {
      await update($, web, () => ({ status: 'starting' as const }))
      let pending = ''
      let failure: string | undefined
      try {
        for await (const chunk of stream) {
          if (chunk.stream === 'stderr') {
            failure = chunk.text.trim().split('\n').at(-1)
            continue
          }
          pending += chunk.text
          for (let end = pending.indexOf('\n'); end >= 0; end = pending.indexOf('\n')) {
            const line = pending.slice(0, end)
            pending = pending.slice(end + 1)
            await handle(JSON.parse(line) as ServerLine)
          }
        }
      } catch (error) {
        failure = String(error)
      }

      if (server === run) {
        server = undefined
        const latest = await read($, web)
        await update($, web, () =>
          failure !== undefined && latest.status === 'starting' ? { status: 'failed' as const, reason: failure } : IDLE,
        )
      }
      resolve(false)
    })().catch(() => resolve(false))
  })

// Opens the review as a web page when there is a browser to open it in, else in the pane.
const show = async ($: EngineInterface, current: Proposal) => {
  if ((await $.env.get('BROWSER')) !== undefined && (await serve($, current))) return { isPlaced: true, where: 'page' } as const
  const opened = await $.ui.open({ id: PANE, title: `Review: ${current.title}` })

  return opened.isPlaced ? ({ isPlaced: true, where: 'pane' } as const) : ({ isPlaced: false, reason: opened.reason } as const)
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.tool.register({
      name: TOOL,
      description: DESCRIPTION,
      inputSchema: SCHEMA,
      isDeferred: false,
    })
    await $.command.register({
      name: 'jm-review-picker',
      description: 'Reopen the review picker pane',
    })
    // A reload killed any page server the previous module started.
    await update($, web, () => IDLE)

    return next(e)
  })

  on('command.run', { command: 'jm-review-picker' }, async $ => {
    const opened = await $.ui.open({ id: PANE, title: 'Review' })

    return { text: opened.isPlaced ? 'Review pane opened.' : `Review pane not shown: ${opened.reason}` }
  })

  on('tool.call', { tool: `mcp__jm-review-picker__${TOOL}` }, async ($, e) => {
    const parsed = parse(e as unknown as Record<string, unknown>)
    if (typeof parsed === 'string') return { deny: parsed }
    const resolved = await resolveCommits($, parsed)
    if (typeof resolved === 'string') return { deny: resolved }

    const shown = await stopServer($)
      .then(() => update($, proposal, () => resolved))
      .then(() => show($, resolved))
      .catch((error: unknown) => ({ isPlaced: false as const, reason: String(error) }))
    const count = resolved.changes.length

    if (!shown.isPlaced)
      return {
        result:
          `The ${count} changes are saved but could not be shown (${shown.reason}). ` +
          'Tell the user to run /jm-review-picker to open the pane, then end your turn.',
      }

    const where = shown.where === 'page' ? "a web page in the user's browser" : 'the Review pane'

    return {
      result:
        `The ${count} changes are shown on ${where}, numbered 1-${count}. ` +
        "End your turn now without repeating them; the user's selection arrives as their next message.",
    }
  }).catch(() => ({ deny: 'The review pane failed to take the changes; list them in chat instead.' }))

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const elements = $.ui.resolve(e)
    const { Box, Text, Button, Link } = elements
    // The mobile app draws no field yet, so the pane there has no note.
    const Input = 'Input' in elements ? elements.Input : undefined
    const current = await read($, proposal)
    const page = await read($, web)

    if (current.status === 'empty')
      return <Text dimColor>No review changes yet. Ask Claude to run a review.</Text>

    const isSent = current.status === 'sent'
    const { chosen, skipped } = selection(current)
    const change = (id: number, fn: (change: Change) => Change) =>
      void update($, proposal, now => ({
        ...now,
        changes: now.changes.map(each => (each.id === id ? fn(each) : each)),
      }))
    // Ticking a change opens its card and unticking closes it; the arrow opens or closes it alone.
    const setAll = (isSelected: boolean) =>
      void update($, proposal, now => ({
        ...now,
        changes: now.changes.map(each => ({ ...each, isSelected, isOpen: isSelected })),
      }))
    const toggle = (id: number) => change(id, each => ({ ...each, isSelected: !each.isSelected, isOpen: !each.isSelected }))
    const fold = (id: number) => change(id, each => ({ ...each, isOpen: !each.isOpen }))
    const setNote = (id: number, note: string) => change(id, each => ({ ...each, note }))
    const send = async () => {
      const now = await read($, proposal)
      if (now.status !== 'open') return
      await stopServer($)
      await answer($, now)
    }
    const openPage = async () => {
      const now = await read($, web)
      if (now.status === 'open') return openUrl($, now.url)
      if (now.status !== 'starting') await serve($, await read($, proposal))
    }

    return (
      <Box flexDirection="column">
        <Text bold>
          {current.title} <Text dimColor>({chosen.length} of {current.changes.length} ticked)</Text>
        </Text>
        {current.changes.map(item => (
          <Box key={`change-${item.id}`} flexDirection="column">
            <Box flexDirection="row" gap={1} paddingTop={1}>
              <Button key={`fold-${item.id}`} plain onPress={() => fold(item.id)}>
                {item.isOpen ? '▾' : '▸'}
              </Button>
              {isSent ? (
                <Text dimColor={!item.isSelected}>
                  {checkbox(item)} {item.id}. {item.title}
                </Text>
              ) : (
                <Button key={`toggle-${item.id}`} plain onPress={() => toggle(item.id)}>
                  {checkbox(item)} {item.id}. {item.title}
                </Button>
              )}
            </Box>
            {hasCommits(current.changes) && (
              <Box paddingLeft={2}>
                <Text dimColor>→ {commitLabel(item.commit)}</Text>
              </Box>
            )}
            {item.isOpen && (
              <Box flexDirection="column" paddingTop={1}>
                {item.reason !== '' && <Text dimColor>{item.reason}</Text>}
                {places(item).map(place => (
                  <Text mono dimColor>
                    {place}
                  </Text>
                ))}
                <Box flexDirection="column" marginTop={1}>
                  {item.kind === 'proposal' ? (
                    <Text>{item.proposal}</Text>
                  ) : (
                    diffLines(item).map(line => (
                      <Text mono backgroundColor={DIFF_BACKGROUND[line.kind]} dimColor={line.kind === 'context'}>
                        {line.text}
                      </Text>
                    ))
                  )}
                </Box>
                {isSent ? (
                  item.note.trim() !== '' && (
                    <Box marginTop={1}>
                      <Text dimColor>Note: {item.note.trim()}</Text>
                    </Box>
                  )
                ) : (
                  Input !== undefined && (
                    <Box marginTop={1}>
                      <Input
                        key={`note-${item.id}`}
                        rows={2}
                        placeholder="Note for Claude (optional)"
                        submitLabel="save"
                        value={item.note}
                        onInput={note => setNote(item.id, note)}
                        onSubmit={note => setNote(item.id, note)}
                      />
                    </Box>
                  )
                )}
              </Box>
            )}
          </Box>
        ))}
        {isSent ? (
          <Box marginTop={1}>
            <Text dimColor>
              Sent: apply {numbers(chosen)}; skip {numbers(skipped)}.
            </Text>
          </Box>
        ) : (
          <Box flexDirection="row" gap={1} flexWrap="wrap" marginTop={1}>
            <Button key="apply" variant="primary" onPress={() => void send()}>
              {chosen.length === 0 ? 'Skip all' : `Apply selected (${chosen.length})`}
            </Button>
            <Button key="all" onPress={() => setAll(true)}>
              Tick all
            </Button>
            <Button key="none" onPress={() => setAll(false)}>
              Untick all
            </Button>
            <Button key="web" onPress={() => void openPage()}>
              {page.status === 'open' ? 'Open page again' : 'Open in browser'}
            </Button>
          </Box>
        )}
        {!isSent && page.status === 'open' && (
          <Text dimColor>
            Page: <Link href={page.url}>{page.url}</Link>. Ticks there are sent when you press Apply on the page.
          </Text>
        )}
        {!isSent && page.status === 'failed' && <Text dimColor>The page could not start: {page.reason}</Text>}
      </Box>
    )
  })
}
