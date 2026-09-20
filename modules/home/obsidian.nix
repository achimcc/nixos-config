# Obsidian mit ObsidiSync — dieselben Notizen auf Laptop und Handy, über den
# eigenen Server (obsi-01, https://obsidian.rusty-vault.de).
#
# DREI SCHICHTEN, und die Trennung ist der Kern dieser Datei:
#
#   1. Was Nix besitzt: die Plugin-Dateien (main.js, manifest.json, styles.css)
#      aus dem GitHub-Release, mit Prüfsumme gepinnt. Sie werden EINZELN
#      verlinkt und nicht als Verzeichnis — ein Symlink auf das
#      Plugin-Verzeichnis zeigte in den Store und wäre schreibgeschützt, und
#      genau dort legt das Plugin sein `data.json` ab. Es könnte sich dann nach
#      dem Login nicht merken, dass es angemeldet ist.
#
#   2. Was die Anwendung besitzt, aber einen Startwert braucht: die Liste der
#      aktiven Plugins, die Serveradresse, die Vault-Registrierung. Das
#      Aktivierungsskript unten schreibt diese Dateien NUR, WENN SIE FEHLEN —
#      Obsidian und das Plugin schreiben sie im Betrieb selbst (Zugangstoken,
#      lastSyncedAt, Plugin-Schalter). Ein bedingungsloses Überschreiben würde
#      bei jedem Rebuild die Anmeldung wegwerfen.
#
#   3. Was gar nicht hierher gehört: das Zugangstoken. obsi-01 läuft mit
#      OIDC-Device-Flow gegen Authentik — `curl https://obsidian.rusty-vault.de/v1/auth/config`
#      antwortet `{"type":"oidc","issuer":"https://auth.rusty-vault.de/application/o/obsidian/",…}`.
#      Es gibt also kein statisches Geheimnis und keinen sops-Eintrag; das
#      Plugin holt sich Issuer und client_id beim ersten Kontakt selbst vom
#      Server. Die Anmeldung als `achim` passiert einmal je Gerät im Dialog.
#
# BRAT VERWALTET OBSIDISYNC NICHT, und das ist eine Entscheidung: Die Version
# pinnt diese Datei, passend zu der, die der Server fährt (`pkgs/obsidisync` im
# homeserver-Repo, Tag v0.15.0). Würde BRAT das Plugin aktualisieren, schriebe
# es über einen Store-Symlink und scheiterte mit „read-only file system". BRAT
# steht hier für andere Beta-Plugins bereit, die es noch nicht im Store gibt.
#
# ZUM START: Obsidian selbst steckt nicht in `home.packages`, sondern als
# Firejail-Wrapper in `modules/network.nix` — dieselbe Bauart wie logseq. Das
# mitgelieferte Firejail-Profil erlaubt `${DOCUMENTS}`, also `~/Dokumente`, und
# deckt den Vault-Pfad unten damit schon ab.

{ config, pkgs, lib, id, osConfig ? null, ... }:

let
  # --- Die drei Adressen, die alles andere bestimmen -----------------------
  vaultName = "Obsidian";
  vaultRel = "Dokumente/${vaultName}";
  vaultPfad = "${config.home.homeDirectory}/${vaultRel}";
  syncServer = "https://obsidian.rusty-vault.de";

  # Der Name, unter dem dieses Gerät in der Sync-Historie auftaucht. Ohne
  # Vorgabe würfelt das Plugin sich einen (`generateComputerName()`), und in
  # der Konfliktanzeige steht dann ein Name, den niemand zuordnen kann.
  geraeteName = if osConfig != null then osConfig.networking.hostName else "nixos";

  # --- Die Plugin-Dateien ---------------------------------------------------
  #
  # `fetchurl` auf die Release-Datei und NICHT `fetchFromGitHub` auf den
  # Quelltext: Beide Plugins sind TypeScript und werden im Release fertig
  # gebaut ausgeliefert. Ein Bau aus dem Quelltext bräuchte hier npm.
  release = { owner, repo, version, datei, hash }: pkgs.fetchurl {
    url = "https://github.com/${owner}/${repo}/releases/download/${version}/${datei}";
    name = "${repo}-${version}-${datei}";
    inherit hash;
  };

  # BRAT — installiert Plugins direkt aus GitHub-Releases, für alles, was es
  # (noch) nicht im Community-Store gibt.
  bratVersion = "2.2.0";
  brat = datei: hash: release {
    owner = "TfTHacker";
    repo = "obsidian42-brat";
    version = bratVersion;
    inherit datei hash;
  };

  # ObsidiSync — der Client zu obsi-01. Die Versionszählung des Projekts ist
  # dreifach: `manifest.json` sagt 0.7.1, der Rust-Server sagt 0.4.0, die TAGS
  # zählen bis v0.15.0. Gepinnt wird der TAG — die einzige Zahl, die Server und
  # Plugin zugleich benennt, und die, auf die auch der Server gepinnt ist.
  obsidisyncVersion = "v0.15.0";
  obsidisync = datei: hash: release {
    owner = "kellertobias";
    repo = "obsidisync";
    version = obsidisyncVersion;
    inherit datei hash;
  };

  # Eine Plugin-Datei wird zu einem Symlink unter `.obsidian/plugins/<id>/`.
  pluginDatei = plugin: datei: quelle: {
    name = "${vaultRel}/.obsidian/plugins/${plugin}/${datei}";
    value = { source = quelle; };
  };

  # --- Die Startwerte -------------------------------------------------------
  #
  # `Object.assign({}, DEFAULT_SETTINGS, loaded)` in `src/main.ts:156` — eine
  # unvollständige `data.json` ist für das Plugin also in Ordnung. Hier stehen
  # nur die Felder, die es NICHT selbst herausfinden kann. `vaultSlug` fehlt
  # bewusst: Das Plugin leitet ihn aus dem Vault-Namen ab (main.ts:39), und ein
  # abweichender Wert hier zeigte auf einen anderen Vorrat auf dem Server.
  syncSaat = pkgs.writeText "obsidisync-data.json" (builtins.toJSON {
    serverUrl = syncServer;
    authorName = id.realName;
    authorEmail = id.email;
    deviceName = geraeteName;
    syncOnStartup = true;
    syncIntervalMinutes = 10;
  });

  # Diese Datei schreibt Obsidian jedes Mal neu, wenn jemand ein Plugin an- oder
  # ausschaltet — deshalb Saat und nicht Symlink.
  pluginListe = pkgs.writeText "obsidian-community-plugins.json" (builtins.toJSON [
    "obsidian42-brat"
    "ios-git-sync"
  ]);

  # Obsidians eigenes Verzeichnis der Vaults. Ohne diesen Eintrag zeigt der
  # erste Start einen Auswahldialog statt der Notizen. Die Kennung ist bei
  # Obsidian eine beliebige Hexfolge; abgeleitet aus dem Pfad bleibt sie über
  # Rebuilds dieselbe.
  vaultKennung = builtins.substring 0 16 (builtins.hashString "md5" vaultPfad);
  vaultRegister = pkgs.writeText "obsidian.json" (builtins.toJSON {
    vaults.${vaultKennung} = {
      path = vaultPfad;
      # Ein fester Zeitstempel (2026-09-20, in Millisekunden): Nix kann die
      # aktuelle Zeit nicht lesen, und Obsidian braucht das Feld nur zum
      # Sortieren der zuletzt geöffneten Vaults.
      ts = 1758326400000;
      open = true;
    };
  });
in
{
  # --- Schicht 1: was Nix besitzt ------------------------------------------
  home.file = lib.listToAttrs [
    (pluginDatei "obsidian42-brat" "main.js"
      (brat "main.js" "sha256-0vtXnU6DFiqhP8FPj4fVk7wilFKb3exup0AR3A+Etyw="))
    (pluginDatei "obsidian42-brat" "manifest.json"
      (brat "manifest.json" "sha256-QvwDMSTq2oHL2nJwYbIunMBYi/mTNmzZwjunL9joHgE="))
    (pluginDatei "obsidian42-brat" "styles.css"
      (brat "styles.css" "sha256-R7vrbhaSCD56xmjod1nHb858MIUmWAiz09NldCGR1fk="))

    # ObsidiSync liefert kein `styles.css` — es gibt keins im Release.
    (pluginDatei "ios-git-sync" "main.js"
      (obsidisync "main.js" "sha256-yi+k13+AbXPsNNnNmkMwKR5tzX/UGDLy4ZcL0UzeWvo="))
    (pluginDatei "ios-git-sync" "manifest.json"
      (obsidisync "manifest.json" "sha256-oRPLSRHe8tvUmrnv1MmM11+XEYEweh2yhwk3d8dolYw="))
  ];

  # Der GNOME-Klick muss auf den gesandkasteten Aufruf zeigen. Das Paket selbst
  # steckt nicht im Profil (nur der Firejail-Wrapper), seine `.desktop`-Datei
  # also auch nicht — ohne diesen Eintrag gäbe es im Menü gar kein Obsidian.
  # Das Symbol als ABSOLUTER PFAD und nicht als Name `obsidian`: Der
  # Symbol-Suchpfad kennt nur, was im Profil liegt.
  xdg.desktopEntries.obsidian = {
    name = "Obsidian";
    genericName = "Notizen";
    comment = "Wissensspeicher, synchronisiert über obsi-01 (Sandbox: Firejail)";
    exec = "obsidian %u";
    icon = "${pkgs.obsidian}/share/icons/hicolor/512x512/apps/obsidian.png";
    terminal = false;
    type = "Application";
    startupNotify = true;
    categories = [ "Office" "Utility" ];
    mimeType = [ "x-scheme-handler/obsidian" ];
    settings.StartupWMClass = "obsidian";
  };

  # --- Schicht 2: Startwerte, nur wenn die Datei fehlt ----------------------
  #
  # `entryAfter [ "linkGeneration" ]` wie bei `sshConfigKopie` in home.nix: Die
  # Plugin-Symlinks müssen liegen, bevor hier Verzeichnisse und Saatdateien
  # dazukommen.
  #
  # `install -m` statt `cp`: Die Dateien kommen aus dem Store und wären sonst
  # schreibgeschützte Kopien — die Anwendung muss sie aber fortschreiben.
  home.activation.obsidianVaultSaat = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run mkdir -p ${lib.escapeShellArg vaultPfad}/.obsidian
    run mkdir -p "$HOME/.config/obsidian"

    # Welche Plugins beim Start geladen werden.
    if [ ! -e ${lib.escapeShellArg vaultPfad}/.obsidian/community-plugins.json ]; then
      run install -m644 ${pluginListe} \
        ${lib.escapeShellArg vaultPfad}/.obsidian/community-plugins.json
    fi

    # Die Serveradresse. Danach gehört die Datei dem Plugin — dort landen
    # Zugangstoken und Synchronisationsstand.
    if [ ! -e ${lib.escapeShellArg vaultPfad}/.obsidian/plugins/ios-git-sync/data.json ]; then
      run install -m600 ${syncSaat} \
        ${lib.escapeShellArg vaultPfad}/.obsidian/plugins/ios-git-sync/data.json
    fi

    # Damit der erste Start die Notizen zeigt und nicht den Auswahldialog.
    if [ ! -e "$HOME/.config/obsidian/obsidian.json" ]; then
      run install -m644 ${vaultRegister} "$HOME/.config/obsidian/obsidian.json"
    fi
  '';
}
