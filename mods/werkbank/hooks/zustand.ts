import type { Lauf } from '../types'

// Vordergrundaufrufe erst ab dieser Dauer zeigen; kurze Aufrufe sind Rauschen.
export const VORDERGRUND_AB_MS = 20_000

export function dauer(ms: number): string {
  const min = Math.floor(ms / 60_000)
  if (min < 1) return `${Math.max(0, Math.floor(ms / 1000))} s`
  if (min < 60) return `${min} min`
  return `${Math.floor(min / 60)} h ${min % 60} min`
}

export function kurz(text: string, n = 60): string {
  const eine = text.replace(/\s+/g, ' ').trim()
  return eine.length > n ? eine.slice(0, n - 1) + '…' : eine
}

// Alles, was gerade laeuft: Hintergrund ganz, Vordergrund ab der Schwelle.
export function sichtbar(hg: Lauf[], vg: Lauf[], now: number): Lauf[] {
  return [...hg, ...vg.filter(l => now - l.seit >= VORDERGRUND_AB_MS)]
}
