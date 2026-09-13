// VPN-Indikator: zeigt den gemessenen WireGuard-Zustand in der Leiste.
// Liest nur Dateien (Status-Dienst, `vpn`, Serverliste) und schaltet nur über `vpn`.
// Fällt die Erweiterung aus, fehlt nur die Anzeige — Kill-Switch und Kürzel sind unabhängig.
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import St from 'gi://St';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Dialog from 'resource:///org/gnome/shell/ui/dialog.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as ModalDialog from 'resource:///org/gnome/shell/ui/modalDialog.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';

import {berechneZustand} from './zustand.js';

const STATUS_DATEI = '/run/vpn/status.json';
const SERVER_DATEI = '/etc/vpn/server.json';
const VPN_BEFEHL = '/run/current-system/sw/bin/vpn';

function leseJson(pfad) {
    try {
        const [ok, inhalt] = GLib.file_get_contents(pfad);
        return ok ? JSON.parse(new TextDecoder().decode(inhalt)) : null;
    } catch (e) {
        return null;
    }
}

function vpn(argument) {
    try {
        const prozess = Gio.Subprocess.new([VPN_BEFEHL, argument], Gio.SubprocessFlags.NONE);
        prozess.wait_async(null, (p, ergebnis) => p.wait_finish(ergebnis));
    } catch (e) {
        Main.notifyError('VPN', `„vpn ${argument}“ ließ sich nicht starten: ${e.message}`);
    }
}

function mib(bytes) {
    return `${(bytes / 1048576).toFixed(1)} MiB`;
}

const VpnIndikator = GObject.registerClass(
class VpnIndikator extends PanelMenu.Button {
    _init() {
        super._init(0.0, 'VPN-Indikator');

        this._label = new St.Label({
            text: '? VPN',
            y_align: Clutter.ActorAlign.CENTER,
            style_class: 'vpn-indikator vpn-unbekannt',
        });
        this.add_child(this._label);

        this._zeileZustand = this._infoZeile();
        this._zeileHandshake = this._infoZeile();
        this._zeileExit = this._infoZeile();
        this._zeileTransfer = this._infoZeile();
        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

        this._serverEintraege = new Map();
        for (const {slot, name} of leseJson(SERVER_DATEI) ?? []) {
            const eintrag = new PopupMenu.PopupMenuItem(`${slot}  ${name}`);
            eintrag.connect('activate', () => vpn(String(slot)));
            this.menu.addMenuItem(eintrag);
            this._serverEintraege.set(slot, eintrag);
        }

        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        const aus = new PopupMenu.PopupMenuItem('0  Aus');
        aus.connect('activate', () => vpn('aus'));
        this.menu.addMenuItem(aus);
        const direkt = new PopupMenu.PopupMenuItem('⚠ Direkt (ungeschützt) …');
        direkt.connect('activate', () => this._bestaetigeDirekt());
        this.menu.addMenuItem(direkt);

        this._aktualisiere();
        this._timer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 1, () => {
            this._aktualisiere();
            return GLib.SOURCE_CONTINUE;
        });
    }

    _infoZeile() {
        const zeile = new PopupMenu.PopupMenuItem('', {reactive: false});
        this.menu.addMenuItem(zeile);
        return zeile;
    }

    _aktualisiere() {
        const status = leseJson(STATUS_DATEI);
        const exit = leseJson(GLib.build_filenamev([GLib.get_user_runtime_dir(), 'vpn', 'exit.json']));
        const z = berechneZustand(status, exit, Math.floor(Date.now() / 1000));

        this._label.text = z.text;
        this._label.style_class = `vpn-indikator vpn-${z.art}`;

        const tunnel = z.art === 'verbunden' || z.art === 'haengt';
        this._zeileZustand.label.text = {
            unbekannt: 'Status-Dienst liefert nichts (älter als 15 s)',
            direkt: 'Direkt — Kill-Switch aus, ungeschützt',
            gesperrt: 'Kein Tunnel — Verkehr gesperrt',
            offen: 'Kein Tunnel — Kill-Switch aus, Verkehr ungeschützt',
            haengt: 'Tunnel aktiv, aber kein frischer Handshake',
            verbunden: 'Verbunden',
        }[z.art];
        this._zeileHandshake.label.text = tunnel
            ? (status.handshake_alter === null ? 'Handshake: nie' : `Handshake vor ${status.handshake_alter} s`)
            : '';
        this._zeileExit.label.text = tunnel ? `Exit: ${z.exitIp ?? 'nicht bestätigt'}` : '';
        this._zeileTransfer.label.text = tunnel && status.rx !== null
            ? `↓ ${mib(status.rx)}   ↑ ${mib(status.tx)}`
            : '';
        for (const zeile of [this._zeileHandshake, this._zeileExit, this._zeileTransfer])
            zeile.visible = zeile.label.text !== '';

        const aktiv = z.art === 'unbekannt' ? null : status.slot;
        for (const [slot, eintrag] of this._serverEintraege) {
            eintrag.setOrnament(slot === aktiv
                ? PopupMenu.Ornament.CHECK
                : PopupMenu.Ornament.NONE);
        }
    }

    _bestaetigeDirekt() {
        const dialog = new ModalDialog.ModalDialog({destroyOnClose: true});
        dialog.contentLayout.add_child(new Dialog.MessageDialogContent({
            title: 'Ungeschützt ins Netz?',
            description: 'Alle Tunnel werden getrennt und der Kill-Switch abgeschaltet — bis du einen ' +
                'Server wählst oder neu startest. Gedacht für die Anmeldung an Captive Portals.',
        }));
        dialog.setButtons([
            {label: 'Abbrechen', action: () => dialog.close(), key: Clutter.KEY_Escape, default: true},
            {label: 'Direkt verbinden', action: () => { dialog.close(); vpn('direkt'); }},
        ]);
        dialog.open();
    }

    destroy() {
        if (this._timer) {
            GLib.Source.remove(this._timer);
            this._timer = null;
        }
        super.destroy();
    }
});

export default class VpnIndikatorExtension extends Extension {
    enable() {
        this._indikator = new VpnIndikator();
        Main.panel.addToStatusArea(this.uuid, this._indikator);
    }

    disable() {
        this._indikator?.destroy();
        this._indikator = null;
    }
}
