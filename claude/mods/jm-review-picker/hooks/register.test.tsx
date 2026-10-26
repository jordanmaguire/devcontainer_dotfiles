import { expect, mock, test } from 'claude-code/testing'

const TOOL = 'mcp__jm-review-picker__propose_changes'

const PANE = {
  plugin: 'jm-review-picker',
  component: 'Pane',
  requestId: 'jm-review-picker',
  props: {
    title: 'Review',
    isFocused: false,
    bodyColumns: 80,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 40 },
    view: {},
  },
} as const

const CHANGES = [
  {
    title: 'Say what membership returns',
    file: 'app/models/user.rb',
    line: 10,
    reason: 'Says what the method returns',
    before: '  # This method gets the thing',
    after: '  # Returns the most recent active membership',
    context_after: '  def membership',
  },
  {
    title: 'Drop the comment that restates the code',
    file: 'app/models/user.rb',
    line: 40,
    reason: 'Restates the code',
    before: '  # increment the counter',
    after: '',
  },
]

test('ticked changes go back to Claude as a prompt, on every surface', async ($, on) => {
  const prompts: string[] = []
  mock.env(on, {})
  on('tool.register', () => ({ value: { tool: TOOL } }))
  on('command.register', () => ({ value: { command: 'jm-review-picker' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('prompt.submit', (_, e) => {
    prompts.push(e.text)

    return { text: e.text }
  })

  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })

  for (const surface of ['terminal', 'desktop', 'vscode'] as const) {
    const called = await $.tool.call({ tool: TOOL, title: 'Comment accuracy', changes: CHANGES })
    expect(String(called.result)).toContain('numbered 1-2')

    const ui = await $.ui.mount({ ...PANE, surface })
    const removed = await ui.find({ type: 'Text', text: '-   # This method gets the thing' })
    expect(removed?.props.backgroundColor).toBe('diffRemoved')
    const added = await ui.find({ type: 'Text', text: '+   # Returns the most recent active membership' })
    expect(added?.props.backgroundColor).toBe('diffAdded')

    await ui.press({ key: 'toggle-2' })
    expect(await ui.find({ type: 'Button', text: /☐ 2\./ })).toBeDefined()
    await ui.press({ key: 'apply' })
    expect(prompts.at(-1)).toBe('Apply these changes from the "Comment accuracy" review: 1.\nSkip: 2.')
    expect(await ui.find({ key: 'apply' })).toBeUndefined()
    await ui.unmount()
  }
})

test('a note typed in the pane goes back with the numbers', async ($, on) => {
  const prompts: string[] = []
  mock.env(on, {})
  on('tool.register', () => ({ value: { tool: TOOL } }))
  on('command.register', () => ({ value: { command: 'jm-review-picker' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('prompt.submit', (_, e) => {
    prompts.push(e.text)

    return { text: e.text }
  })
  await $.session.start({ cwd: '/', surface: 'vscode', isInteractive: true })
  await $.tool.call({ tool: TOOL, title: 'Comment accuracy', changes: CHANGES })

  const ui = await $.ui.mount({ ...PANE, surface: 'vscode' })
  await ui.input({ key: 'note-2', text: 'Kee', kind: 'change' })
  await ui.input({ key: 'note-2', text: 'Keep it: the counter\nis not obvious', kind: 'change' })
  await ui.press({ key: 'toggle-2' })
  await ui.press({ key: 'apply' })

  expect(prompts).toEqual([
    [
      'Apply these changes from the "Comment accuracy" review: 1.',
      'Skip: 2.',
      '',
      'My notes on these changes; answer each one, and where a note asks for something else, do that:',
      '- 2: Keep it: the counter',
      '  is not obvious',
    ].join('\n'),
  ])
  await ui.press({ key: 'fold-2' })
  expect(await ui.find({ type: 'Text', text: /Note: Keep it/ })).toBeDefined()
  await ui.unmount()
})

test('a proposal is drawn as a description beside the edits', async ($, on) => {
  mock.env(on, {})
  on('tool.register', () => ({ value: { tool: TOOL } }))
  on('command.register', () => ({ value: { command: 'jm-review-picker' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })

  await $.tool.call({
    tool: TOOL,
    title: 'Class composition',
    changes: [
      CHANGES[0],
      {
        title: 'Move CSV building out of the controller',
        reason: 'The controller builds and sends the export itself',
        proposal: 'Extract the CSV building into Exports::ParticipantCsv and call it from the controller.',
        files: ['app/controllers/exports_controller.rb', 'app/services/exports/participant_csv.rb'],
      },
    ],
  })

  for (const surface of ['terminal', 'desktop', 'vscode'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect(await ui.find({ type: 'Button', text: /☑ 2\. Move CSV building out of the controller/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: 'app/services/exports/participant_csv.rb' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Extract the CSV building/ })).toBeDefined()
    await ui.unmount()
  }
})

test('a malformed list is refused with the reason', async ($, on) => {
  on('tool.register', () => ({ value: { tool: TOOL } }))
  on('command.register', () => ({ value: { command: 'jm-review-picker' } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })

  const called = await $.tool.call({
    tool: TOOL,
    title: 'Comment accuracy',
    changes: [{ title: 'Fix it', file: 'a.rb', line: 0, reason: '', before: 'x', after: 'y' }],
  })
  expect(called.deny).toBe('changes[0].line must be a positive integer.')

  const untitled = await $.tool.call({
    tool: TOOL,
    title: 'Comment accuracy',
    changes: [{ file: 'a.rb', line: 1, reason: '', before: 'x', after: 'y' }],
  })
  expect(untitled.deny).toBe('changes[0].title must be a non-empty string.')
})

const URL = 'http://127.0.0.1:40000/abc/'
const BROWSER = '/vscode/bin/helpers/browser.sh'
const CLI = '/vscode/bin/remote-cli/code'

test('with $BROWSER set, the review opens as a page that sends the same reply as the pane', async ($, on) => {
  const prompts: string[] = []
  const opened: string[][] = []
  const served: string[] = []
  const panes: string[] = []
  mock.env(on, { BROWSER })
  on('tool.register', () => ({ value: { tool: TOOL } }))
  on('command.register', () => ({ value: { command: 'jm-review-picker' } }))
  on('ui.open', (_, e) => {
    panes.push(e.id)

    return { value: { isPlaced: true } }
  })
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('prompt.submit', (_, e) => {
    prompts.push(e.text)

    return { text: e.text }
  })
  on('process.run', (_, e) => {
    opened.push([...e.argv])
    const stdout = e.argv[1] === '--list-extensions' ? 'anthropic.claude-code\n' : ''

    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  // Stands for server/review-server.mjs: prints its URL, then the numbers ticked on the page.
  on('process.spawn', async function* (_, e) {
    served.push(e.input ?? '')
    yield { stream: 'stdout' as const, text: `{"url":"${URL}"}\n{"sel` }
    yield { stream: 'stdout' as const, text: 'ected":[2]}\n' }

    return { value: { code: 0, signal: null } }
  })

  await $.session.start({ cwd: '/', surface: 'vscode', isInteractive: true })
  const called = await $.tool.call({ tool: TOOL, title: 'Comment accuracy', changes: CHANGES })

  expect(String(called.result)).toContain("a web page in the user's browser")
  expect(panes).toEqual([])
  expect(JSON.parse(served[0] ?? '{}').title).toBe('Comment accuracy')
  expect(opened).toEqual([
    [CLI, '--list-extensions'],
    [BROWSER, URL],
  ])

  const ui = await $.ui.mount({ ...PANE, surface: 'vscode' })
  expect(prompts).toEqual(['Apply these changes from the "Comment accuracy" review: 2.\nSkip: 1.'])
  expect(await ui.find({ type: 'Text', text: /Sent: apply 2; skip 1\./ })).toBeDefined()
  await ui.unmount()
})

test('notes written on the page come back with the numbers', async ($, on) => {
  const prompts: string[] = []
  mock.env(on, { BROWSER })
  on('tool.register', () => ({ value: { tool: TOOL } }))
  on('command.register', () => ({ value: { command: 'jm-review-picker' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('prompt.submit', (_, e) => {
    prompts.push(e.text)

    return { text: e.text }
  })
  on('process.run', () => ({
    value: { exitCode: 0, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false },
  }))
  on('process.spawn', async function* () {
    yield { stream: 'stdout' as const, text: `{"url":"${URL}"}\n` }
    yield { stream: 'stdout' as const, text: '{"selected":[],"notes":{"1":"Why not say which membership?"}}\n' }

    return { value: { code: 0, signal: null } }
  })

  await $.session.start({ cwd: '/', surface: 'vscode', isInteractive: true })
  await $.tool.call({ tool: TOOL, title: 'Comment accuracy', changes: CHANGES })

  const ui = await $.ui.mount({ ...PANE, surface: 'vscode' })
  await ui.press({ key: 'fold-1' })
  expect(await ui.find({ type: 'Text', text: /Note: Why not say/ })).toBeDefined()
  await ui.unmount()
  expect(prompts).toEqual([
    [
      'Skip every change from the "Comment accuracy" review (1, 2). Make no edits beyond what a note asks for.',
      '',
      'My notes on these changes; answer each one, and where a note asks for something else, do that:',
      '- 1: Why not say which membership?',
    ].join('\n'),
  ])
})

test('with the VS Code extension installed, the page opens through it', async ($, on) => {
  const opened: string[][] = []
  mock.env(on, { BROWSER })
  on('tool.register', () => ({ value: { tool: TOOL } }))
  on('command.register', () => ({ value: { command: 'jm-review-picker' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('process.run', (_, e) => {
    opened.push([...e.argv])
    const stdout = e.argv[1] === '--list-extensions' ? 'anthropic.claude-code\ndusc.review-picker-browser\n' : ''

    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('process.spawn', async function* () {
    yield { stream: 'stdout' as const, text: `{"url":"${URL}"}\n` }

    return { value: { code: 0, signal: null } }
  })

  await $.session.start({ cwd: '/', surface: 'vscode', isInteractive: true })
  await $.tool.call({ tool: TOOL, title: 'Comment accuracy', changes: CHANGES })

  expect(opened.at(-1)).toEqual([
    BROWSER,
    'vscode://dusc.review-picker-browser/open?url=http%3A%2F%2F127.0.0.1%3A40000%2Fabc%2F',
  ])
})

test('when the page server cannot start, the review falls back to the pane', async ($, on) => {
  const panes: string[] = []
  mock.env(on, { BROWSER })
  on('tool.register', () => ({ value: { tool: TOOL } }))
  on('command.register', () => ({ value: { command: 'jm-review-picker' } }))
  on('ui.open', (_, e) => {
    panes.push(e.id)

    return { value: { isPlaced: true } }
  })
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('process.spawn', async function* () {
    yield { stream: 'stderr' as const, text: 'node: not found\n' }

    return { value: { code: 127, signal: null } }
  })

  await $.session.start({ cwd: '/', surface: 'vscode', isInteractive: true })
  const called = await $.tool.call({ tool: TOOL, title: 'Comment accuracy', changes: CHANGES })

  expect(String(called.result)).toContain('the Review pane')
  expect(panes).toEqual(['jm-review-picker'])
})

test('an unticked change folds away, and the arrow opens it again', async ($, on) => {
  mock.env(on, {})
  on('tool.register', () => ({ value: { tool: TOOL } }))
  on('command.register', () => ({ value: { command: 'jm-review-picker' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  await $.session.start({ cwd: '/', surface: 'vscode', isInteractive: true })
  await $.tool.call({ tool: TOOL, title: 'Comment accuracy', changes: CHANGES })

  const ui = await $.ui.mount({ ...PANE, surface: 'vscode' })
  const removed = { type: 'Text', text: '-   # increment the counter' } as const
  expect(await ui.find(removed)).toBeDefined()

  await ui.press({ key: 'toggle-2' })
  expect(await ui.find(removed)).toBeUndefined()
  expect(await ui.find({ type: 'Button', text: /☐ 2\. Drop the comment/ })).toBeDefined()

  await ui.press({ key: 'fold-2' })
  expect(await ui.find(removed)).toBeDefined()
  await ui.press({ key: 'fold-2' })
  expect(await ui.find(removed)).toBeUndefined()

  await ui.press({ key: 'toggle-2' })
  expect(await ui.find(removed)).toBeDefined()
  await ui.unmount()
})

const ADD = 'a'.repeat(40)
const FIXUP_OF_ADD = 'b'.repeat(40)

// Stands for git in a repository whose branch adds a commit and a fixup of it over master.
const mockGit = (on: Parameters<Parameters<typeof test>[1]>[1]) =>
  on('process.run', (_, e) => {
    const [, command] = e.argv
    const stdout =
      command === 'symbolic-ref'
        ? 'origin/master\n'
        : command === 'merge-base'
          ? `${'0'.repeat(40)}\n`
          : command === 'log'
            ? `${FIXUP_OF_ADD}\0bbbbbbb\0fixup! Add memberships\n${ADD}\0aaaaaaa\0Add memberships\n`
            : ''

    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })

test('each change shows its commit beside its title, folded or not', async ($, on) => {
  mock.env(on, {})
  mockGit(on)
  on('tool.register', () => ({ value: { tool: TOOL } }))
  on('command.register', () => ({ value: { command: 'jm-review-picker' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  await $.session.start({ cwd: '/', surface: 'vscode', isInteractive: true })

  const [first, second] = CHANGES
  const called = await $.tool.call({
    tool: TOOL,
    title: 'Comment accuracy',
    changes: [
      // A fixup of the fixup is planned against the commit both fix.
      { ...first, commit: { fixup: 'bbbbbbb' } },
      { ...second, commit: { message: 'Drop comments that restate the code\n\nThey repeat the method names.' } },
      { ...second, line: 50, title: 'Keep as is', commit: undefined },
    ],
  })
  expect(String(called.result)).toContain('numbered 1-3')

  const ui = await $.ui.mount({ ...PANE, surface: 'vscode' })
  expect(await ui.find({ type: 'Text', text: '→ fixup! Add memberships (aaaaaaa)' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: '→ New commit: Drop comments that restate the code' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: '→ Not committed' })).toBeDefined()

  await ui.press({ key: 'toggle-1' })
  expect(await ui.find({ type: 'Text', text: '-   # This method gets the thing' })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: '→ fixup! Add memberships (aaaaaaa)' })).toBeDefined()
  await ui.unmount()
})

test('a fixup of a commit that is not on the branch is refused', async ($, on) => {
  mock.env(on, {})
  mockGit(on)
  on('tool.register', () => ({ value: { tool: TOOL } }))
  on('command.register', () => ({ value: { command: 'jm-review-picker' } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  await $.session.start({ cwd: '/', surface: 'vscode', isInteractive: true })

  const called = await $.tool.call({
    tool: TOOL,
    title: 'Comment accuracy',
    changes: [{ ...CHANGES[0], commit: { fixup: 'c0ffee1' } }],
  })
  expect(called.deny).toBe(
    'changes[0].commit.fixup c0ffee1 is not a commit on this branch; fix up only a commit between the merge-base and ' +
      'HEAD, or give a `message` for a new commit.',
  )
})
