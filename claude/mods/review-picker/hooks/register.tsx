import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Change, Edit, Proposal, Web } from '../types'

const PANE = 'review-picker'
const TOOL = 'propose_changes'
const EMPTY: Proposal = { title: '', changes: [], status: 'empty' }
const proposal = atom({ plugin: 'review-picker', key: 'proposal' } as const, EMPTY)
const IDLE: Web = { status: 'idle' }
const web = atom({ plugin: 'review-picker', key: 'web' } as const, IDLE)

// The running web page server, if any. It dies with the module, so a reload starts with none.
let server: { stop: () => void } | undefined

const DESCRIPTION = [
  'Show a numbered list of suggested changes in a side pane, where the user ticks which ones',
  'to carry out. Use it whenever a review produces suggestions for the user to accept or reject.',
  '',
  'Each change is one of:',
  '  - An edit: an exact text replacement (`file`, `line`, `before`, `after`), drawn as a diff.',
  '  - A proposal: a change too broad for one replacement, such as extracting a class or moving',
  '    a method (`proposal`, and the `files` it touches), drawn as a description.',
  '',
  'After calling it, end your turn without repeating the list in chat. The user answers with a',
  'message naming the change numbers to apply and to skip; carry out only those. Numbers follow',
  'the order of `changes`, starting at 1. Calling again replaces the list in the pane.',
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
        required: ['reason'],
        properties: {
          reason: {
            type: 'string',
            description: 'One short sentence on why the change helps',
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

const location = (change: Change): string => {
  if (change.kind === 'edit') return `${change.file}:${change.line}`
  const [first, ...rest] = change.files
  if (first === undefined) return 'Proposal'

  return rest.length === 0 ? `Proposal: ${first}` : `Proposal: ${first} +${rest.length} more`
}

const parseChange = (raw: unknown, index: number): Change | string => {
  const item = (raw ?? {}) as Record<string, unknown>
  const { file, line, reason, before, after, context_after, proposal: text, files } = item
  const at = `changes[${index}]`
  const id = index + 1
  if (typeof reason !== 'string') return `${at}.reason must be a string.`

  if (text !== undefined) {
    if (typeof text !== 'string' || text.trim() === '') return `${at}.proposal must be a non-empty string.`
    if (files !== undefined && !(Array.isArray(files) && files.every(path => typeof path === 'string')))
      return `${at}.files must be an array of paths when given.`

    return { kind: 'proposal', id, reason, proposal: text.trim(), files: (files as string[]) ?? [], isSelected: true }
  }

  if (typeof file !== 'string' || file === '') return `${at} needs either \`proposal\` or the edit fields; file is missing.`
  if (typeof line !== 'number' || !Number.isInteger(line) || line < 1) return `${at}.line must be a positive integer.`
  if (typeof before !== 'string' || typeof after !== 'string') return `${at}.before and ${at}.after must be strings.`
  if (before === after) return `${at} changes nothing: before and after are the same.`
  if (context_after !== undefined && typeof context_after !== 'string')
    return `${at}.context_after must be a string when given.`

  return { kind: 'edit', id, file, line, reason, before, after, contextAfter: context_after ?? '', isSelected: true }
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

const numbers = (changes: Change[]): string =>
  changes.length === 0 ? 'none' : changes.map(change => change.id).join(', ')

const selection = (current: Proposal) => {
  const chosen = current.changes.filter(change => change.isSelected)
  const skipped = current.changes.filter(change => !change.isSelected)

  return { chosen, skipped }
}

const message = (current: Proposal): string => {
  const { chosen, skipped } = selection(current)
  if (chosen.length === 0)
    return `Skip every change from the "${current.title}" review (${numbers(skipped)}). Make no edits.`

  return [
    `Apply these changes from the "${current.title}" review: ${numbers(chosen)}.`,
    `Skip: ${numbers(skipped)}.`,
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

type ServerLine = { url?: string; selected?: number[] }

// Serves the review on 127.0.0.1 from server/review-server.mjs, which prints its URL once listening and the ticked
// numbers when the user presses Apply on the page.
const serve = async ($: EngineInterface, current: Proposal) => {
  const stream = $.process.spawn({
    argv: ['node', `${$.plugin.root}/server/review-server.mjs`],
    input: JSON.stringify({ title: current.title, changes: current.changes }),
  })
  const run = { stop: () => void stream.return({ code: null, signal: null }) }
  server = run
  await update($, web, () => ({ status: 'starting' as const }))

  const handle = async (line: ServerLine) => {
    if (server !== run) return
    if (line.url !== undefined) {
      await update($, web, () => ({ status: 'open' as const, url: line.url as string }))
      await openUrl($, line.url)
    }
    if (line.selected !== undefined) {
      const ticked = new Set(line.selected)
      const latest = await read($, proposal)
      await answer($, {
        ...latest,
        changes: latest.changes.map(change => ({ ...change, isSelected: ticked.has(change.id) })),
      })
    }
  }

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

  if (server !== run) return
  server = undefined
  const latest = await read($, web)
  await update($, web, () =>
    failure !== undefined && latest.status === 'starting' ? { status: 'failed' as const, reason: failure } : IDLE,
  )
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
      name: 'review-picker',
      description: 'Reopen the review picker pane',
    })
    // A reload killed any page server the previous module started.
    await update($, web, () => IDLE)

    return next(e)
  })

  on('command.run', { command: 'review-picker' }, async $ => {
    const opened = await $.ui.open({ id: PANE, title: 'Review' })

    return { text: opened.isPlaced ? 'Review pane opened.' : `Review pane not shown: ${opened.reason}` }
  })

  on('tool.call', { tool: `mcp__review-picker__${TOOL}` }, async ($, e) => {
    const parsed = parse(e as unknown as Record<string, unknown>)
    if (typeof parsed === 'string') return { deny: parsed }

    const opened = await stopServer($)
      .then(() => update($, proposal, () => parsed))
      .then(() => $.ui.open({ id: PANE, title: `Review: ${parsed.title}` }))
      .catch((error: unknown) => ({ isPlaced: false as const, reason: String(error) }))
    const count = parsed.changes.length

    if (!opened.isPlaced)
      return {
        result:
          `The ${count} changes are saved but the pane could not be shown (${opened.reason}). ` +
          'Tell the user to run /review-picker to open it, then end your turn.',
      }

    return {
      result:
        `The ${count} changes are shown in the Review pane, numbered 1-${count}. ` +
        "End your turn now without repeating them; the user's selection arrives as their next message.",
    }
  }).catch(() => ({ deny: 'The review pane failed to take the changes; list them in chat instead.' }))

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button, Link } = $.ui.resolve(e)
    const current = await read($, proposal)
    const page = await read($, web)

    if (current.status === 'empty')
      return <Text dimColor>No review changes yet. Ask Claude to run a review.</Text>

    const isSent = current.status === 'sent'
    const { chosen, skipped } = selection(current)
    const setAll = (isSelected: boolean) =>
      void update($, proposal, now => ({
        ...now,
        changes: now.changes.map(change => ({ ...change, isSelected })),
      }))
    const toggle = (id: number) =>
      void update($, proposal, now => ({
        ...now,
        changes: now.changes.map(change =>
          change.id === id ? { ...change, isSelected: !change.isSelected } : change,
        ),
      }))
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
        {current.changes.map(change => (
          <Box key={`change-${change.id}`} flexDirection="column">
            <Box paddingY={1}>
              {isSent ? (
                <Text dimColor={!change.isSelected}>
                  {checkbox(change)} {change.id}. {location(change)}
                </Text>
              ) : (
                <Button key={`toggle-${change.id}`} plain onPress={() => toggle(change.id)}>
                  {checkbox(change)} {change.id}. <Text dimColor>{location(change)}</Text>
                </Button>
              )}
            </Box>
            {change.reason !== '' && (
              <Box marginBottom={1}>
                <Text dimColor>{change.reason}</Text>
              </Box>
            )}
            {change.kind === 'proposal' ? (
              <Text>{change.proposal}</Text>
            ) : (
              diffLines(change).map(line => (
                <Text mono backgroundColor={DIFF_BACKGROUND[line.kind]} dimColor={line.kind === 'context'}>
                  {line.text}
                </Text>
              ))
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
