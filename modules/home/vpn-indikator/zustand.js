// Reine Zustandslogik der VPN-Anzeige — ohne GNOME-Importe, damit sie mit gjs testbar ist.
// Spec: docs/superpowers/specs/2026-09-13-wireguard-statt-proton-gui-design.md

// WireGuard verhandelt bei Verkehr spätestens alle 120 s neu (Keepalive 25 s sorgt für Verkehr).
export const HANDSHAKE_GRENZE_S = 180;
// Der Status-Dienst schreibt alle 2 s; älter als das heißt: er läuft nicht.
export const STATUS_GRENZE_S = 15;

export function berechneZustand(status, exit, jetzt) {
    if (!status || typeof status.zeit !== 'number' || jetzt - status.zeit > STATUS_GRENZE_S)
        return {art: 'unbekannt', text: '? VPN', exitIp: null};

    if (status.direkt)
        return {art: 'direkt', text: '⚠ DIREKT', exitIp: null};

    if (status.slot === null) {
        // Ohne Kill-Switch ist "kein Tunnel" nicht gesperrt, sondern offen.
        return status.killswitch
            ? {art: 'gesperrt', text: '⛔ gesperrt', exitIp: null}
            : {art: 'offen', text: '⚠ OFFEN', exitIp: null};
    }

    const name = status.name ?? `wg-${status.slot}`;
    const exitIp = exit && exit.slot === status.slot ? exit.ip : null;

    if (status.handshake_alter === null || status.handshake_alter >= HANDSHAKE_GRENZE_S)
        return {art: 'haengt', text: `⚠ ${name}`, exitIp};

    return {art: 'verbunden', text: `🔒 ${name}`, exitIp};
}
