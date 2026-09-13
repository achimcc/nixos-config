// Test der Zustandslogik. Läuft mit `gjs -m` — ohne GNOME Shell, beim Bau des Pakets.
import System from 'system';
import {berechneZustand} from './zustand.js';

let fehler = 0;
function pruefe(beschreibung, ist, soll) {
    const a = JSON.stringify(ist);
    const b = JSON.stringify(soll);
    if (a === b) {
        print(`ok      ${beschreibung}`);
    } else {
        printerr(`FEHLER  ${beschreibung}: ist ${a}, soll ${b}`);
        fehler++;
    }
}

const jetzt = 1000;
const basis = {
    zeit: 998, slot: 2, name: 'XX-2', handshake_alter: 30,
    rx: 1, tx: 1, direkt: false, killswitch: true,
};
const exit2 = {slot: 2, ip: '192.0.2.1', zeit: 990};

pruefe('kein Status → unbekannt',
    berechneZustand(null, null, jetzt),
    {art: 'unbekannt', text: '? VPN', exitIp: null});
pruefe('Status 16 s alt → unbekannt',
    berechneZustand({...basis, zeit: 984}, exit2, jetzt),
    {art: 'unbekannt', text: '? VPN', exitIp: null});
pruefe('Status genau 15 s alt → noch gültig',
    berechneZustand({...basis, zeit: 985}, exit2, jetzt).art,
    'verbunden');
pruefe('direkt geht vor Tunnel',
    berechneZustand({...basis, direkt: true}, exit2, jetzt),
    {art: 'direkt', text: '⚠ DIREKT', exitIp: null});
pruefe('kein Tunnel, Kill-Switch an → gesperrt',
    berechneZustand({...basis, slot: null, name: null, handshake_alter: null}, null, jetzt),
    {art: 'gesperrt', text: '⛔ gesperrt', exitIp: null});
pruefe('kein Tunnel, Kill-Switch aus → offen',
    berechneZustand({...basis, slot: null, name: null, handshake_alter: null, killswitch: false}, null, jetzt),
    {art: 'offen', text: '⚠ OFFEN', exitIp: null});
pruefe('verbunden mit passender Exit-IP',
    berechneZustand(basis, exit2, jetzt),
    {art: 'verbunden', text: '🔒 XX-2', exitIp: '192.0.2.1'});
pruefe('Exit-IP eines anderen Slots wird nicht gezeigt',
    berechneZustand(basis, {...exit2, slot: 5}, jetzt),
    {art: 'verbunden', text: '🔒 XX-2', exitIp: null});
pruefe('nie Handshake → hängt',
    berechneZustand({...basis, handshake_alter: null}, exit2, jetzt),
    {art: 'haengt', text: '⚠ XX-2', exitIp: '192.0.2.1'});
pruefe('Handshake genau 180 s → hängt',
    berechneZustand({...basis, handshake_alter: 180}, exit2, jetzt).art,
    'haengt');
pruefe('Handshake 179 s → verbunden',
    berechneZustand({...basis, handshake_alter: 179}, exit2, jetzt).art,
    'verbunden');
pruefe('fehlender Name → Interfacename',
    berechneZustand({...basis, name: null}, null, jetzt).text,
    '🔒 wg-2');

System.exit(fehler === 0 ? 0 : 1);
