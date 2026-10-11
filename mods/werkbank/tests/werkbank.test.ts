import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'

// Was unter dem Plugin steht: eine Sitzung, die alles annimmt.
function welt(on: On) {
  const uhr = mock.clock(on, { now: 1_000_000 })
  on('session.start', (_$, e) => ({ cwd: e.cwd }))
  on('command.register', (_$, e) => ({ value: { command: e.name } }))
  on('tool.register', (_$, e) => ({ value: { tool: `mcp__werkbank__${e.name}` } }))
  on('ui.open', () => ({ value: { isPlaced: false } }))
  on('ui.status', () => ({ value: undefined }))
  on('ui.toast', () => ({ value: undefined }))
  on('classic.Stop', () => ({}))
  // Kein Git, kein lotse im Test: jedes Programm fehlt.
  on('process.run', () => ({ value: { exitCode: 127, stdout: '', stderr: 'nicht da' } }))
  return uhr
}

test('ein Hintergrundlauf erscheint in /laufend und verschwindet nach Stop', async ($, on) => {
  const uhr = welt(on)
  on('tool.call', () => ({ result: 'gestartet' }))
  await $.session.start({ cwd: '/tmp', surface: 'terminal', isInteractive: true })

  await $.tool.call({
    tool: 'Bash',
    command: 'lotse run --class=deploy -- hs-deploy server',
    description: 'Deploy server im Slot',
    run_in_background: true,
  })
  await uhr.advance(12 * 60_000)
  await $.classic.Stop({
    stop_hook_active: false,
    background_tasks: [{ id: 'b1', type: 'shell', status: 'running', description: 'Deploy server im Slot' }],
  })
  const mit = await $.command.run({ command: 'laufend', args: '' })
  // Die Startzeit kommt aus dem tool.call, nicht aus dem Stop.
  expect(mit.text).toContain('shell: Deploy server im Slot · 12 min')

  await $.classic.Stop({ stop_hook_active: false, background_tasks: [] })
  const ohne = await $.command.run({ command: 'laufend', args: '' })
  expect(ohne.text).toBe('Diese Sitzung hat nichts laufen.')
})

test('ein Vordergrundaufruf zaehlt erst ab 20 s', async ($, on) => {
  const uhr = welt(on)
  let fertig: () => void = () => {}
  on('tool.call', () => new Promise(r => (fertig = () => r({ result: 'ok' }))))
  await $.session.start({ cwd: '/tmp', surface: 'terminal', isInteractive: true })

  const lauf = $.tool.call({ tool: 'Bash', command: 'nix build', description: 'Systembau' })
  await uhr.settle()
  expect((await $.command.run({ command: 'laufend', args: '' })).text).toBe('Diese Sitzung hat nichts laufen.')
  await uhr.advance(5 * 60_000)
  expect((await $.command.run({ command: 'laufend', args: '' })).text).toContain('Bash: Systembau · 5 min')
  fertig()
  await lauf
  expect((await $.command.run({ command: 'laufend', args: '' })).text).toBe('Diese Sitzung hat nichts laufen.')
})

test('/fertig ohne Git-Repo sagt das, statt etwas zu behaupten', async ($, on) => {
  welt(on)
  await $.session.start({ cwd: '/tmp', surface: 'terminal', isInteractive: true })
  const r = await $.command.run({ command: 'fertig', args: '' })
  expect(r.text).toContain('Kein Git-Repo')
})

// Eine Uebergabe bis zum Werkzeugaufruf, mit Mitschrift von Einreichen,
// Kopieren und /clear.
async function uebergabeBisWerkzeug($: any, on: On, args: string) {
  const uhr = welt(on)
  const eingereicht: string[] = []
  const kopiert: string[] = []
  const befehle: string[] = []
  on('prompt.submit', (_$, e) => {
    eingereicht.push(e.text)
    return { text: e.text }
  })
  on('ui.copy', (_$, e) => {
    kopiert.push(e.text)
    return { value: { isCopied: true } }
  })
  on('command.run', { command: 'clear' }, () => {
    befehle.push('clear')
    return { text: '' }
  })
  await $.session.start({ cwd: '/tmp', surface: 'terminal', isInteractive: true })
  const r = await $.command.run({ command: 'uebergabe', args })
  await uhr.advance(1000)
  const w = await $.tool.call({ tool: 'mcp__werkbank__startprompt', text: 'Weiter mit X, lies zuerst UEBERGABE.md' })
  return { uhr, r, w, eingereicht, kopiert, befehle }
}

test('/uebergabe: Blatt-Auftrag, dann nach dem Zug /clear und der Startprompt als erster Auftrag', async ($, on) => {
  const t = await uebergabeBisWerkzeug($, on, 'Subagent je Aufgabe')
  expect(t.r.text).toContain('automatisch')
  expect(t.eingereicht.length).toBe(1)
  expect(t.eingereicht[0]).toContain('STAND BEI DER ÜBERGABE')
  expect(t.eingereicht[0]).toContain('Arbeitsweise laut Nutzer: Subagent je Aufgabe')
  expect(t.kopiert).toEqual(['Weiter mit X, lies zuerst UEBERGABE.md'])
  expect(String(t.w.result)).toContain('leert der Mod den Kontext')

  // Noch kein Zugende: nichts passiert.
  await t.uhr.advance(60_000)
  expect(t.befehle).toEqual([])
  await $.classic.Stop({ stop_hook_active: false, background_tasks: [] })
  await t.uhr.advance(9_000)
  expect(t.befehle).toEqual([])
  await t.uhr.advance(2_000)
  expect(t.befehle).toEqual(['clear'])
  expect(t.eingereicht[1]).toBe('Weiter mit X, lies zuerst UEBERGABE.md')
})

test('/uebergabe: Tippen in der Frist bricht den Wechsel ab', async ($, on) => {
  const t = await uebergabeBisWerkzeug($, on, '')
  await $.classic.Stop({ stop_hook_active: false, background_tasks: [] })
  await t.uhr.advance(3_000)
  await $.prompt.submit({ text: 'halt, noch nicht' })
  await t.uhr.advance(20_000)
  expect(t.befehle).toEqual([])
})

test('/uebergabe nur-blatt: Zwischenablage, kein /clear', async ($, on) => {
  const t = await uebergabeBisWerkzeug($, on, 'nur-blatt Subagent je Aufgabe')
  expect(t.r.text).toContain('nur Blatt')
  expect(t.eingereicht[0]).toContain('Arbeitsweise laut Nutzer: Subagent je Aufgabe')
  expect(t.eingereicht[0]).not.toContain('nur-blatt')
  expect(String(t.w.result)).toContain('Zwischenablage')
  await $.classic.Stop({ stop_hook_active: false, background_tasks: [] })
  await t.uhr.advance(20_000)
  expect(t.befehle).toEqual([])
})
