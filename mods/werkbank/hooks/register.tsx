import { atom, read, update } from 'claude-code'
import type {
  BackgroundTaskSummary,
  CommandRunInput,
  CommandRunResult,
  EngineInterface as Engine,
  Register,
  ToolCallInput,
  Timer,
  ToolCallResult,
  RenderElement,
  RenderInput,
} from 'claude-code'

import type { Lauf } from '../types'
import { dauer, kurz, sichtbar } from './zustand'

// $ darf nicht ueber einen Import wandern (Regel des Validators), deshalb
// steht alles, was $ benutzt, in dieser einen Datei.

// ---- Zustand der Sitzung ----

const hintergrund = atom({ plugin: 'werkbank', key: 'hintergrund' } as const, [])
const vordergrund = atom({ plugin: 'werkbank', key: 'vordergrund' } as const, [])
const starts = atom({ plugin: 'werkbank', key: 'starts' } as const, [])
const lotse = atom({ plugin: 'werkbank', key: 'lotse' } as const, '')
const lotseStand = atom({ plugin: 'werkbank', key: 'lotseStand' } as const, 0)
// Takt fuer die Anzeige: der Tick schreibt die Uhrzeit, das zeichnet die
// Laufzeiten neu, ohne dass der Render-Hook selbst schreibt.
const jetzt = atom({ plugin: 'werkbank', key: 'jetzt' } as const, 0)

// Ein Befehl darf keinen Zug einreichen, solange sein Hook den Zug haelt;
// der Timer reicht ihn ein, sobald der Befehl fertig ist.
function nachDemBefehl($: Engine, prompt: { text: string }): void {
  $.clock.after(100, () => {
    $.prompt.submit(prompt).catch(err => $.ui.toast(`werkbank: Einreichen scheiterte: ${String(err)}`))
  })
}

// ---- git und Prozesse ----
type ProzessLauf = { code: number; out: string; err: string }

async function run($: Engine, argv: string[], timeoutMs = 30_000, cwd?: string): Promise<ProzessLauf> {
  try {
    const r = await $.process.run(argv, { timeoutMs, cwd })
    return { code: r.exitCode, out: r.stdout.trim(), err: r.stderr.trim() }
  } catch (err) {
    return { code: -1, out: '', err: String(err) }
  }
}

type Ort = {
  wurzel: string
  zweig: string
  istWorktree: boolean
  istHomeserver: boolean
}

// Wo steht die Sitzung? undefined, wenn nicht in einem Git-Repo.
async function ort($: Engine): Promise<Ort | undefined> {
  const w = await run($, ['git', 'rev-parse', '--show-toplevel'])
  if (w.code !== 0) return undefined
  const zweig = (await run($, ['git', 'branch', '--show-current'])).out || '(losgeloest)'
  const dir = (await run($, ['git', 'rev-parse', '--path-format=absolute', '--git-dir'])).out
  const common = (await run($, ['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'])).out
  const url = (await run($, ['git', 'remote', 'get-url', 'origin'])).out
  return {
    wurzel: w.out,
    zweig,
    istWorktree: dir !== '' && dir !== common,
    istHomeserver: /achimcc\/homeserver(\.git)?$/.test(url),
  }
}

// Die Commits, die auf diesem Zweig selbst entstanden sind (ohne Merges von
// main), als Liste geaenderter Dateien. undefined, wenn der Zweig keinen
// Anfang im Reflog hat.
async function eigeneDateien($: Engine, zweig: string): Promise<string[] | undefined> {
  const log = await run($, ['git', 'reflog', 'show', '--format=%H', `refs/heads/${zweig}`])
  if (log.code !== 0 || log.out === '') return undefined
  const anfang = log.out.split('\n').pop()!
  const d = await run($, ['git', 'log', '--no-merges', '--first-parent', '--name-only', '--format=', `${anfang}..HEAD`])
  if (d.code !== 0) return undefined
  return [...new Set(d.out.split('\n').filter(Boolean))]
}

// ---- /laufend: was diese Sitzung laufen hat ----

const PANE = 'werkbank-laufend'
const TICK_MS = 15_000
// Ab dieser Laufzeit meldet ein Toast den Lauf einmal von selbst.
const MELDEN_AB_MS = 30 * 60_000
// Nicht zugeordnete Starts verfallen nach dieser Zeit.
const START_VERFALL_MS = 6 * 3600_000

// Welche Aufrufe eine Hintergrundaufgabe starten, und wie sie heissen.
function hintergrundStart(e: any): { art: string; text: string } | undefined {
  switch (String(e.tool)) {
    case 'Bash':
      return e.run_in_background === true
        ? { art: 'shell', text: e.description || e.command || 'Bash' }
        : undefined
    case 'Agent':
      return e.run_in_background === true
        ? { art: 'agent', text: e.description || e.subagent_type || 'Agent' }
        : undefined
    case 'Monitor':
      return { art: 'monitor', text: e.description || e.command || 'Monitor' }
    case 'Workflow':
      return { art: 'workflow', text: e.name || e.description || 'Workflow' }
    default:
      return undefined
  }
}

function vordergrundText(e: any): string {
  switch (String(e.tool)) {
    case 'Bash':
      return e.description || e.command || 'Bash'
    case 'Agent':
      return `Agent: ${e.description || e.subagent_type || ''}`
    default:
      return String(e.tool)
  }
}

async function lotseHolen($: Engine): Promise<void> {
  let text: string
  try {
    const r = await $.process.run(['lotse', 'status'], { timeoutMs: 15_000 })
    text = (r.stdout + r.stderr).trim() || '(keine Ausgabe)'
    if (r.exitCode !== 0) text = `lotse status: Exit ${r.exitCode}\n${text}`
  } catch (err) {
    text = `lotse status nicht ausfuehrbar: ${String(err)}`
  }
  const now = await $.clock.now()
  await update($, lotse, () => text)
  await update($, lotseStand, () => now)
}

// Nur fuer diese Ladung des Moduls: welche Laeufe schon gemeldet sind.
const gemeldet = new Set<string>()

async function tick($: Engine): Promise<void> {
  const now = await $.clock.now()
  await update($, jetzt, () => now)
  const liste = sichtbar(await read($, hintergrund), await read($, vordergrund), now)
  if (liste.length === 0) {
    $.ui.status(undefined)
    return
  }
  const aeltester = liste.reduce((a, b) => (b.seit < a.seit ? b : a))
  const rest = liste.length > 1 ? ` (+${liste.length - 1})` : ''
  $.ui.status(`⏳ ${kurz(aeltester.text, 40)} · ${dauer(now - aeltester.seit)}${rest} — /laufend`)
  for (const l of liste) {
    if (now - l.seit >= MELDEN_AB_MS && !gemeldet.has(l.id)) {
      gemeldet.add(l.id)
      $.ui.toast(`Läuft seit ${dauer(now - l.seit)}: ${kurz(l.text, 70)}`)
    }
  }
}

async function laufendStart($: Engine): Promise<void> {
  await $.command.register({
    name: 'laufend',
    description: 'Zeigt, was diese Sitzung gerade laufen hat, mit Laufzeit, dazu lotse status',
  })
  $.clock.every(TICK_MS, () => void tick($))
}

async function laufendBefehl($: Engine): Promise<CommandRunResult> {
  await lotseHolen($)
  await tick($)
  await $.ui.open({ id: PANE, title: 'Laufend' })
  const now = await $.clock.now()
  const liste = sichtbar(await read($, hintergrund), await read($, vordergrund), now)
  const zeilen = liste.map(l => `- ${l.art}: ${kurz(l.text, 80)} · ${dauer(now - l.seit)}`)
  return { text: liste.length === 0 ? 'Diese Sitzung hat nichts laufen.' : zeilen.join('\n') }
}

async function laufendWerkzeug($: Engine, e: ToolCallInput, next: (e: ToolCallInput) => Promise<ToolCallResult>): Promise<ToolCallResult> {
  // Werkzeugaufrufe in Subagenten zaehlen nicht einzeln; der Agent selbst zaehlt.
  if (e.agentId !== undefined) return next(e)
  const now = await $.clock.now()
  const hg = hintergrundStart(e)
  if (hg !== undefined) {
    await update($, starts, list =>
      [...list.filter(s => now - s.seit < START_VERFALL_MS), { text: hg.text, seit: now }].slice(-50),
    )
    return next(e)
  }
  const id = e.tool_use_id ?? `${e.tool}-${now}`
  const lauf: Lauf = { id, art: String(e.tool), text: vordergrundText(e), seit: now }
  await update($, vordergrund, list => [...list, lauf])
  try {
    return await next(e)
  } finally {
    await update($, vordergrund, list => list.filter(l => l.id !== id))
  }
}

// Am Ende jedes Zuges nennt die Engine die Aufgaben, die noch laufen.
// Das ist die Wahrheit; die Starts liefern nur die Startzeit dazu.
async function laufendStop($: Engine, e: { background_tasks?: BackgroundTaskSummary[] }): Promise<void> {
  const now = await $.clock.now()
  const alt = await read($, hintergrund)
  const offen = [...(await read($, starts))]
  const neu: Lauf[] = (e.background_tasks ?? []).map(t => {
    const bekannt = alt.find(l => l.id === t.id)
    if (bekannt !== undefined) return bekannt
    const text = t.description || t.command || t.name || t.agent_type || t.type
    const i = offen.findIndex(s => s.text === t.description || s.text === t.command || s.text === t.name)
    const seit = offen[i]?.seit ?? now
    if (i >= 0) offen.splice(i, 1)
    return { id: t.id, art: t.type, text, seit }
  })
  await update($, hintergrund, () => neu)
  await update($, starts, () => offen.filter(s => now - s.seit < START_VERFALL_MS))
  await tick($)
}

async function laufendPane($: Engine, e: RenderInput<'Pane'>): Promise<RenderElement> {
  const { Box, Text, Button } = $.ui.resolve(e)
  const now = (await read($, jetzt)) || Date.now()
  const liste = sichtbar(await read($, hintergrund), await read($, vordergrund), now)
  const lotseText = await read($, lotse)
  const stand = await read($, lotseStand)
  const breite = Math.max(20, (e.props.bodyColumns ?? 60) - 4)
  return (
    <Box flexDirection="column">
      <Text bold>Diese Sitzung</Text>
      {liste.length === 0 && <Text dimColor>nichts laufend</Text>}
      {liste.map(l => (
        <Text key={l.id}>
          {dauer(now - l.seit).padStart(9)} <Text dimColor>{l.art}</Text> {kurz(l.text, breite - 20)}
        </Text>
      ))}
      <Text> </Text>
      <Box>
        <Text bold>lotse status </Text>
        <Text dimColor>{stand ? `vor ${dauer(now - stand)} ` : ''}</Text>
        <Button key="neu" label="neu laden" onPress={() => void lotseHolen($)} />
      </Box>
      {lotseText.split('\n').slice(0, 30).map((z, i) => (
        <Text key={`l${i}`} dimColor>
          {kurz(z, breite)}
        </Text>
      ))}
    </Box>
  )
}

// ---- /fertig: Abschluss messen, dann Worktree weg ----

type Urteil = 'ok' | 'rot' | 'gelb' | 'offen'
type Punkt = { name: string; urteil: Urteil; text: string }

const ZEICHEN: Record<Urteil, string> = { ok: '✔', rot: '✘', gelb: '!', offen: '?' }

type GhLauf = { headSha: string; status: string; conclusion: string; workflowName: string }

async function ciPunkt($: Engine): Promise<Punkt> {
  const name = 'CI'
  const r = await run($, [
    'gh', 'run', 'list', '--branch', 'main', '--event', 'push', '--limit', '30',
    '--json', 'headSha,status,conclusion,workflowName',
  ])
  if (r.code !== 0) return { name, urteil: 'offen', text: `gh run list scheiterte: ${kurz(r.err, 80)}` }
  let laeufe: GhLauf[]
  try {
    laeufe = JSON.parse(r.out)
  } catch {
    return { name, urteil: 'offen', text: 'Antwort von gh nicht lesbar' }
  }
  // Der aelteste Push auf main, der HEAD enthaelt, ist der, der die Arbeit brachte.
  const shas = [...new Set(laeufe.map(l => l.headSha))]
  let treffer: string | undefined
  for (const sha of shas) {
    const a = await run($, ['git', 'merge-base', '--is-ancestor', 'HEAD', sha])
    if (a.code === 0) treffer = sha
    else if (treffer !== undefined) break
  }
  if (treffer === undefined) return { name, urteil: 'offen', text: 'kein Lauf unter den letzten 30 enthält HEAD' }
  const eigene = laeufe.filter(l => l.headSha === treffer)
  const rot = eigene.filter(l => l.status === 'completed' && !['success', 'skipped', 'cancelled'].includes(l.conclusion))
  const laeuft = eigene.filter(l => l.status !== 'completed')
  const abgebrochen = eigene.filter(l => l.conclusion === 'cancelled')
  const kurzSha = treffer.slice(0, 8)
  if (rot.length > 0) return { name, urteil: 'rot', text: `${kurzSha}: rot in ${rot.map(l => l.workflowName).join(', ')}` }
  if (laeuft.length > 0) return { name, urteil: 'gelb', text: `${kurzSha}: läuft noch (${laeuft.map(l => l.workflowName).join(', ')})` }
  if (abgebrochen.length > 0) return { name, urteil: 'gelb', text: `${kurzSha}: abgebrochen (${abgebrochen.map(l => l.workflowName).join(', ')})` }
  return { name, urteil: 'ok', text: `${kurzSha}: grün (${eigene.map(l => l.workflowName).join(', ')})` }
}

async function deployPunkt($: Engine): Promise<Punkt> {
  const name = 'Deploy server'
  const r = await run(
    $,
    [
      'ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10', 'colmena-deploy@server',
      'nixos-version --configuration-revision; readlink -f /run/current-system; readlink -f /nix/var/nix/profiles/system',
    ],
    25_000,
  )
  if (r.code !== 0) return { name, urteil: 'offen', text: `ssh scheiterte (Exit ${r.code}): ${kurz(r.err, 80)}` }
  const [rev = '', laufend = '', profil = ''] = r.out.split('\n').map(s => s.trim())
  if (!/^[0-9a-f]{40}$/.test(rev)) return { name, urteil: 'offen', text: `laufender Stand unklar: ${kurz(rev, 40)}` }
  const kurzRev = rev.slice(0, 8)
  if ((await run($, ['git', 'cat-file', '-e', `${rev}^{commit}`])).code !== 0) {
    return { name, urteil: 'offen', text: `Server läuft ${kurzRev}, lokal unbekannt` }
  }
  if ((await run($, ['git', 'merge-base', '--is-ancestor', 'HEAD', rev])).code !== 0) {
    return { name, urteil: 'rot', text: `Server läuft ${kurzRev}, enthält HEAD nicht` }
  }
  if (laufend !== profil) {
    return { name, urteil: 'gelb', text: `${kurzRev} enthält HEAD, aber nur per deploy test (Profil ≠ /run/current-system)` }
  }
  return { name, urteil: 'ok', text: `Server läuft ${kurzRev}, enthält HEAD` }
}

async function fertigStart($: Engine): Promise<void> {
  await $.command.register({
    name: 'fertig',
    description: 'Prüft: committed, in origin/main, CI grün, deployt, Newsletter — dann Worktree weg',
    argumentHint: '[ohne-newsletter] [ohne-deploy]',
  })
}

async function fertigBefehl($: Engine, e: CommandRunInput): Promise<CommandRunResult> {
  const args = e.args.toLowerCase()
  const wo = await ort($)
  if (wo === undefined) return { text: 'Kein Git-Repo im Arbeitsverzeichnis dieser Sitzung.' }

  const punkte: Punkt[] = []
  const status = await run($, ['git', 'status', '--porcelain'])
  const zeilen = status.out.split('\n').filter(Boolean)
  const geaendert = zeilen.filter(z => !z.startsWith('??'))
  const ungetrackt = zeilen.filter(z => z.startsWith('??'))
  punkte.push(
    geaendert.length > 0
      ? { name: 'Committed', urteil: 'rot', text: `${geaendert.length} geänderte Datei(en): ${kurz(geaendert.slice(0, 3).join(', '), 80)}` }
      : { name: 'Committed', urteil: 'ok', text: 'Arbeitsbaum ohne Änderungen' },
  )
  if (ungetrackt.length > 0) {
    punkte.push({ name: 'Ungetrackt', urteil: 'gelb', text: `${ungetrackt.length}: ${kurz(ungetrackt.slice(0, 3).join(', '), 80)}` })
  }

  const fetch = await run($, ['git', 'fetch', 'origin', '--quiet'], 60_000)
  if (fetch.code !== 0) {
    punkte.push({ name: 'In origin/main', urteil: 'offen', text: `git fetch scheiterte: ${kurz(fetch.err, 80)}` })
  } else {
    const drin = (await run($, ['git', 'merge-base', '--is-ancestor', 'HEAD', 'origin/main'])).code === 0
    const vor = (await run($, ['git', 'rev-list', '--count', 'origin/main..HEAD'])).out
    punkte.push(
      drin
        ? { name: 'In origin/main', urteil: 'ok', text: 'gemergt und gepusht' }
        : { name: 'In origin/main', urteil: 'rot', text: `${vor} Commit(s) fehlen auf origin/main` },
    )
    if (drin) punkte.push(await ciPunkt($))
    if (drin && wo.istHomeserver && !args.includes('ohne-deploy')) punkte.push(await deployPunkt($))
  }

  // Auf main gibt es keinen eigenen Zweig: der Reflog von main enthaelt die
  // Commits aller Sitzungen, Newsletter- und VPS-Urteil waeren fremde.
  const eigene = wo.zweig === 'main' ? undefined : await eigeneDateien($, wo.zweig)
  if (wo.istHomeserver && eigene !== undefined) {
    const wirkt = eigene.some(d => /^(hosts|modules|lib|pkgs)\//.test(d))
    const eintrag = eigene.some(d => d.startsWith('newsletter/'))
    if (eintrag) punkte.push({ name: 'Newsletter', urteil: 'ok', text: 'Eintrag im Zweig' })
    else if (wirkt && !args.includes('ohne-newsletter')) {
      punkte.push({ name: 'Newsletter', urteil: 'gelb', text: 'kein Eintrag — bewusst? dann /fertig ohne-newsletter' })
    }
    if (eigene.some(d => d.startsWith('hosts/vps/'))) {
      punkte.push({ name: 'Deploy vps', urteil: 'gelb', text: 'Zweig ändert hosts/vps — nicht geprüft, hs-deploy vps gelaufen?' })
    }
  }

  const hg = await read($, hintergrund)
  if (hg.length > 0) {
    punkte.push({ name: 'Hintergrund', urteil: 'gelb', text: `läuft noch: ${kurz(hg.map(l => l.text).join(', '), 80)}` })
  }

  const alleOk = punkte.every(p => p.urteil === 'ok')
  const kopf = `${wo.istWorktree ? 'Worktree' : 'Baum'} ${wo.wurzel} · Zweig ${wo.zweig}`
  const tabelle = punkte.map(p => `${ZEICHEN[p.urteil]} ${p.name.padEnd(15)} ${p.text}`).join('\n')

  if (alleOk && wo.istWorktree) {
    nachDemBefehl($, {
      text:
        `/fertig hat alles belegt:\n${tabelle}\n\n` +
        `Räum den Worktree ${wo.wurzel} weg (ExitWorktree mit Entfernen; ist die Sitzung nicht per ` +
        `EnterWorktree darin, git worktree remove aus dem Hauptbaum) und lösche den gemergten Zweig ` +
        `${wo.zweig}. Miss danach, dass Verzeichnis und Zweig weg sind, und melde es in einem Satz.`,
    })
    return { text: `${kopf}\n${tabelle}\n\nAlles belegt — Worktree wird weggeräumt.` }
  }
  const fazit = !wo.istWorktree
    ? `${alleOk ? 'Alles belegt.' : 'Nicht fertig.'} Kein Worktree — nichts wegzuräumen.${wo.zweig === 'main' ? ' Auf main: Newsletter und VPS nicht zuordenbar, nicht geprüft.' : ''}`
    : 'Nicht fertig — Worktree bleibt.'
  return {
    text: `${kopf}\n${tabelle}\n\n${fazit}`,
    context: alleOk ? undefined : [`Ergebnis von /fertig (vom Mod gemessen, nicht behauptet):\n${tabelle}`],
  }
}

// ---- /uebergabe: an einen frischen Agenten weiterreichen ----

const WERKZEUG = 'startprompt'
// Nach so vielen Millisekunden leert der Mod den Kontext; tippt der Nutzer
// vorher etwas, bleibt alles stehen.
const WECHSEL_NACH_MS = 10_000

// Gilt fuer diese Ladung des Moduls; ein /clear laedt es nicht neu.
let uebergabeAutomatisch = false
let wartenderStart: string | undefined
let wechselAbbrechen: Timer | undefined

// Nach dem Zug, der den Startprompt abgegeben hat: /clear, dann der Startprompt
// als erster Auftrag der frischen Sitzung.
async function wechseln($: Engine, text: string): Promise<void> {
  wechselAbbrechen = undefined
  try {
    await $.command.run({ command: 'clear' })
  } catch (err) {
    $.ui.toast(`/clear aus dem Mod scheiterte (${String(err)}) — selbst /clear tippen, der Startprompt liegt in der Zwischenablage.`)
    return
  }
  await $.prompt.submit({ text }).catch(err =>
    $.ui.toast(`Startprompt nicht eingereicht (${String(err)}) — er liegt in der Zwischenablage.`),
  )
}

function wechselPlanen($: Engine): void {
  const text = wartenderStart
  if (text === undefined) return
  wartenderStart = undefined
  $.ui.toast(`Übergabe fertig — in ${WECHSEL_NACH_MS / 1000} s wird der Kontext geleert. Etwas tippen bricht ab.`)
  wechselAbbrechen = $.clock.after(WECHSEL_NACH_MS, () => void wechseln($, text))
}

async function uebergabeStart($: Engine): Promise<void> {
  await $.command.register({
    name: 'uebergabe',
    description: 'Stand ins Übergabeblatt, dann /clear und der frische Agent übernimmt (nur-blatt: ohne /clear)',
    argumentHint: '[nur-blatt] [Hinweis für den Nachfolger, z. B. Subagent je Aufgabe]',
  })
  await $.tool.register({
    name: WERKZEUG,
    description:
      'Legt den Startprompt fuer den Agenten, der diese Arbeit in einer frischen Sitzung uebernimmt, ' +
      'in die Zwischenablage des Nutzers. Nur im Ablauf von /uebergabe aufrufen, als letzten Schritt.',
    inputSchema: {
      type: 'object',
      properties: { text: { type: 'string', description: 'Der Startprompt, fertig zum Einfuegen' } },
      required: ['text'],
    },
    isDeferred: false,
  })
}

async function uebergabeWerkzeug($: Engine, e: ToolCallInput): Promise<ToolCallResult> {
  const text = String((e as { text?: unknown }).text ?? '').trim()
  if (text === '') return { deny: 'text ist leer' }
  // Die Zwischenablage ist der Rueckfall, auch im automatischen Ablauf.
  let kopiert = (await $.ui.copy({ text })).isCopied
  if (!kopiert) {
    const wl = await $.process.run(['wl-copy'], { stdin: text, timeoutMs: 5_000 }).catch(() => undefined)
    kopiert = wl !== undefined && wl.exitCode === 0
  }
  if (uebergabeAutomatisch) {
    uebergabeAutomatisch = false
    wartenderStart = text
    return {
      result:
        'Angenommen. Nach diesem Zug leert der Mod den Kontext und gibt den Startprompt dem Nachfolger. ' +
        'Schreib nur noch einen Satz an den Nutzer und rufe kein Werkzeug mehr auf.',
    }
  }
  if (kopiert) return { result: 'Startprompt liegt in der Zwischenablage. Sag dem Nutzer, dass er mit /clear oder einer neuen Sitzung weitermachen kann.' }
  return { result: 'Zwischenablage nicht erreichbar. Gib den Startprompt im Chat als Codeblock aus.' }
}

async function uebergabeBefehl($: Engine, e: CommandRunInput): Promise<CommandRunResult> {
  const wo = await ort($)
  const fakten: string[] = []
  if (wo === undefined) {
    fakten.push('Kein Git-Repo im Arbeitsverzeichnis.')
  } else {
    fakten.push(`${wo.istWorktree ? 'Worktree' : 'Hauptbaum'}: ${wo.wurzel}, Zweig ${wo.zweig}`)
    const st = await run($, ['git', 'status', '--porcelain'])
    const n = st.out.split('\n').filter(z => z !== '' && !z.startsWith('??')).length
    fakten.push(n > 0 ? `${n} uncommittete Änderung(en)` : 'Arbeitsbaum ohne Änderungen')
    const vor = await run($, ['git', 'rev-list', '--count', 'origin/main..HEAD'])
    if (vor.code === 0) fakten.push(`${vor.out} Commit(s) noch nicht auf origin/main (Stand des letzten fetch)`)
  }
  const hg = await read($, hintergrund)
  const laeufe = hg.map(l => `- ${l.art}: ${kurz(l.text, 100)}`)

  const nurBlatt = /(^|\s)nur-blatt(\s|$)/.test(e.args)
  uebergabeAutomatisch = !nurBlatt
  wartenderStart = undefined
  const hinweis = e.args.replace(/(^|\s)nur-blatt(?=\s|$)/, ' ').trim()
  const auftrag = [
    'Übergabe: Diese Sitzung endet, ein frischer Agent übernimmt die Aufgabe. Arbeite nicht weiter an der Sache selbst.',
    '',
    'Gemessen vom Mod:',
    ...fakten.map(f => `- ${f}`),
    laeufe.length > 0
      ? `Diese Hintergrundläufe sterben mit der Sitzung:\n${laeufe.join('\n')}\nHalte für jeden fest, wie der Nachfolger sein Ergebnis prüft (nicht nur, dass er lief).`
      : '- Keine Hintergrundläufe.',
    '',
    'Schritte:',
    '1. Schreib den Stand ins Übergabeblatt dieser Arbeit — das, das die Sitzung schon benutzt; gibt es keines, ' +
      'lege UEBERGABE.md in der Wurzel des Worktrees an. Ganz oben ein Abschnitt „STAND BEI DER ÜBERGABE <Datum Uhrzeit>“: ' +
      'was erledigt und belegt ist (mit Beleg), was offen ist als nummerierte Todo-Liste in Reihenfolge, ' +
      'der genaue Wiederaufsetzpunkt, Fallen dieser Sitzung, und was NICHT erneut versucht werden soll.',
    '2. Zieh die passende Stand-Memory nach, falls es eine gibt.',
    '3. Committe das Blatt im Zweig (gezielt stagen, kein git add -A). Nicht pushen, nicht deployen, wenn das nicht ohnehin anstand.',
    `4. Formuliere den Startprompt: Repo, Worktree samt Zweig, „Lies zuerst <Blatt>, Abschnitt STAND BEI DER ÜBERGABE“, ` +
      'die nächste Aufgabe, die Arbeitsweise. Kurz — das Blatt trägt die Einzelheiten.' +
      (hinweis !== '' ? ` Arbeitsweise laut Nutzer: ${hinweis}` : ''),
    `5. Ruf mcp__werkbank__${WERKZEUG} mit dem Startprompt auf. Danach nur noch ein Satz an den Nutzer.`,
  ].join('\n')

  nachDemBefehl($, { text: auftrag })
  const wie = nurBlatt ? 'nur Blatt und Zwischenablage' : 'danach /clear und Nachfolger automatisch'
  return { text: `Übergabe angestoßen (${wie}).\n${fakten.join('\n')}${laeufe.length > 0 ? `\nLaufend: ${laeufe.length}` : ''}` }
}

// ---- Anmeldung ----

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    await laufendStart($)
    await fertigStart($)
    await uebergabeStart($)
    return started
  })

  on('command.run', { command: 'laufend' }, $ => laufendBefehl($))
  on('command.run', { command: 'fertig' }, ($, e) => fertigBefehl($, e))
  on('command.run', { command: 'uebergabe' }, ($, e) => uebergabeBefehl($, e))

  on('tool.call', { tool: 'mcp__werkbank__startprompt' }, ($, e) => uebergabeWerkzeug($, e))
  on('tool.call', ($, e, next) => laufendWerkzeug($, e, next))

  // Am Ende jedes Zuges nennt die Engine die Aufgaben, die noch laufen.
  on('classic.Stop', async ($, e, next) => {
    await laufendStop($, e)
    wechselPlanen($)
    return next(e)
  })

  // Tippt der Nutzer waehrend der Frist, bleibt die Sitzung, wie sie ist.
  on('prompt.submit', ($, e, next) => {
    if (wechselAbbrechen !== undefined && e.origin?.kind !== 'plugin') {
      wechselAbbrechen.cancel()
      wechselAbbrechen = undefined
      $.ui.toast('Übergabe-Wechsel abgebrochen — der Startprompt liegt in der Zwischenablage.')
    }
    return next(e)
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, ($, e) => laufendPane($, e))
}
