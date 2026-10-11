// Ein Lauf: Hintergrundaufgabe (Bash im Hintergrund, Agent, Monitor,
// Workflow) oder ein langer Vordergrundaufruf.
export type Lauf = {
  id: string
  art: string
  text: string
  seit: number
}

// Ein Start aus tool.call, der noch keiner Aufgabe aus classic.Stop
// zugeordnet ist. Zugeordnet wird ueber die Beschreibung.
export type Start = {
  text: string
  seit: number
}

declare module 'claude-code' {
  interface PluginState {
    werkbank: {
      hintergrund: Lauf[]
      vordergrund: Lauf[]
      starts: Start[]
      lotse: string
      lotseStand: number
      jetzt: number
    }
  }
}
