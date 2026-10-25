# Trade Republic: Steuerdokumente automatisch nach Paperless (2026-10-25,
# Steuer-Repo ~/Dokumente/Steuer, Punkt 3 der Werkzeug-Recherche).
#
# WAS ES TUT: Ein User-Timer startet monatlich `tr-steuerdokumente`. Das laedt
# mit pytr (inoffizielle TR-Web-API, nixpkgs) ALLE Timeline-PDFs nach
# ~/Dokumente/Trade Republic/ (lokales Archiv, pytr ueberspringt Vorhandenes)
# und laedt davon NUR die Steuerdokumente — Jahressteuerbescheinigung,
# Steuerreport, Steuerkorrekturen — ueber die REST-API in Paperless hoch, mit
# Tag steuer-<Jahr>. Kontoauszuege, Abrechnungen, Kosteninformationen bleiben
# nur im Archiv (Achims Entscheidung 2026-10-25: sonst betitelt paperless-gpt
# Hunderte Abrechnungen).
#
# LOGIN: pytr meldet sich per Web-Login v2 an (`--v2`): TR schickt einen Push in
# die App, pytr wartet auf die Bestaetigung. Die Sitzung (Cookies in ~/.pytr)
# haelt eine Weile, laeuft aber immer wieder ab. Dann kommt beim Timerlauf eine
# Desktop-Meldung „In der TR-App bestaetigen"; verpasst → Meldung „Login
# abgelaufen", nachholen mit `tr-steuerdokumente` im Terminal.
#
# GEHEIMNISSE: Telefonnummer und PIN stehen in sops (`pytr-credentials`, zwei
# Zeilen: +49…, PIN) und erscheinen als ~/.pytr/credentials (Symlink nach
# /run/secrets, 0400). pytr schreibt diese Datei nur mit `--store_credentials`,
# das hier nie gesetzt wird. VOR DEM ERSTEN `nrs` MUSS DER EINTRAG IN
# secrets/secrets.yaml STEHEN, sonst bricht sops-install-secrets die
# Aktivierung ab. Der Paperless-Token hat EINE Quelle wie beim MCP
# (paperless-mcp-token in homeserver-secrets/secrets/papier.yaml, TPM-Identitaet),
# s. mcp-paperless.nix.
#
# Jahr des Tags: steht im Titel eine Jahreszahl, die; sonst bei
# Bescheinigung/Report das Vorjahr des Dokumentdatums (die
# Jahressteuerbescheinigung 2025 kam am 2026-02-03), bei Steuerkorrekturen das
# Jahr des Dokumentdatums. Hochgeladen wird erst ab `abJahr`; was davor liegt,
# ist veranlagt. Jede Zuordnung steht in der Abschlussmeldung und im Journal
# (`journalctl --user -u tr-steuerdokumente`).
{ pkgs, id, ... }:

let
  abJahr = 2025;

  skript = pkgs.writeShellApplication {
    name = "tr-steuerdokumente";
    runtimeInputs = with pkgs; [ pytr curl jq sops age-plugin-tpm coreutils gnugrep findutils libnotify ];
    text = ''
      archiv="$HOME/Dokumente/Trade Republic"
      zustand="''${XDG_STATE_HOME:-$HOME/.local/state}/tr-steuerdokumente"
      geheim=''${HOMESERVER_SECRETS:-$HOME/Projects/homeserver-secrets}
      url=https://papiere.rusty-vault.de
      lauf="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/tr-steuerdokumente"
      umask 077
      mkdir -p "$archiv" "$zustand" "$lauf"
      touch "$zustand/hochgeladen"

      melden() { notify-send --app-name="Trade Republic" "$@" 2>/dev/null || true; }

      if [ ! -r "$HOME/.pytr/credentials" ]; then
        echo "tr-steuerdokumente: ~/.pytr/credentials fehlt — pytr-credentials in sops eingetragen und nrs gelaufen?" >&2
        melden --urgency=critical "TR-Steuerdokumente" "Zugangsdaten fehlen (sops pytr-credentials)."
        exit 1
      fi

      # --- 1. Alles ins Archiv. Meldet pytr, dass es auf den Push wartet, eine
      # Desktop-Meldung; der Rest der Ausgabe geht unveraendert ins Journal.
      set +e
      timeout 15m pytr dl_docs --v2 "$archiv" < /dev/null 2>&1 | while IFS= read -r zeile; do
        printf '%s\n' "$zeile"
        case "$zeile" in
          *[Cc]"onfirm the login"*) melden --urgency=critical "Trade Republic" "Login in der TR-App bestätigen (pytr wartet)." ;;
        esac
      done
      dl=''${PIPESTATUS[0]}
      set -e
      if [ "$dl" -ne 0 ]; then
        echo "tr-steuerdokumente: pytr dl_docs endete mit $dl" >&2
        melden --urgency=critical "TR-Steuerdokumente" "Download fehlgeschlagen (exit $dl). Login abgelaufen? Im Terminal: tr-steuerdokumente"
        exit 1
      fi

      # --- 2. Paperless-Token (wie mcp-paperless.nix), Kopf ueber Datei statt argv.
      SOPS_AGE_KEY_FILE=/home/${id.username}/.config/sops/age/tpm-identity.txt \
        sops -d --extract '["paperless-mcp-token"]' "$geheim/secrets/papier.yaml" | tr -d '\n' > "$lauf/token"
      grep -qE '^[0-9a-f]{40}$' "$lauf/token" || { echo "tr-steuerdokumente: paperless-mcp-token unbrauchbar" >&2; exit 1; }
      kopf="$lauf/kopf"
      printf 'Authorization: Token %s\n' "$(cat "$lauf/token")" > "$kopf"
      trap 'rm -f "$kopf" "$lauf/token"' EXIT

      api() { curl -sS --fail-with-body --max-time 60 -H @"$kopf" "$@"; }

      tag_id() {
        local name=$1 tid
        tid=$(api -G "$url/api/tags/" --data-urlencode "name__iexact=$name" | jq -r '.results[0].id // empty')
        if [ -z "$tid" ]; then
          # matching_algorithm 0 = keine automatische Zuordnung
          tid=$(api -H 'Content-Type: application/json' -d "{\"name\":\"$name\",\"matching_algorithm\":0}" "$url/api/tags/" | jq -r '.id')
        fi
        printf '%s' "$tid"
      }

      # --- 3. Nur Steuerdokumente hochladen, jedes genau einmal.
      neu=0; liste=""
      while IFS= read -r -d "" datei; do
        rel=''${datei#"$archiv"/}
        grep -qxF -- "$rel" "$zustand/hochgeladen" && continue
        name=$(basename "$datei" .pdf)
        datumsjahr=''${name:0:4}
        [[ $datumsjahr =~ ^20[0-9]{2}$ ]] || { echo "übersprungen, kein Datum vorn: $rel" >&2; continue; }
        if [[ ''${name:17} =~ (^|[^0-9])(20[0-9]{2})([^0-9]|$) ]]; then
          jahr=''${BASH_REMATCH[2]}
        elif [[ ''${rel,,} == *steuerkorrektur* ]]; then
          jahr=$datumsjahr
        else
          jahr=$((datumsjahr - 1))
        fi
        if [ "$jahr" -lt ${toString abJahr} ]; then
          printf '%s\n' "$rel" >> "$zustand/hochgeladen"
          continue
        fi
        tid=$(tag_id "steuer-$jahr")
        api -F "document=@\"$datei\"" -F "title=Trade Republic $name" -F "tags=$tid" \
          "$url/api/documents/post_document/" > /dev/null
        printf '%s\n' "$rel" >> "$zustand/hochgeladen"
        echo "hochgeladen: $rel → steuer-$jahr"
        neu=$((neu + 1)); liste+="$name → steuer-$jahr"$'\n'
      done < <(find "$archiv" -type f -iname '*.pdf' -print0 | grep -z -iE 'steuerbescheinigung|steuerreport|steuerkorrektur')

      if [ "$neu" -gt 0 ]; then
        melden "TR-Steuerdokumente: $neu nach Paperless" "$liste"
      fi
      echo "tr-steuerdokumente: fertig, $neu neue Steuerdokumente hochgeladen"
    '';
  };
in
{
  sops.secrets."pytr-credentials" = {
    owner = id.username;
    mode = "0400";
  };

  environment.systemPackages = [ skript ];

  home-manager.users.${id.username} =
    { config, ... }:
    {
      home.file.".pytr/credentials".source =
        config.lib.file.mkOutOfStoreSymlink "/run/secrets/pytr-credentials";

      systemd.user.services.tr-steuerdokumente = {
        Unit = {
          Description = "Trade Republic: Dokumente archivieren, Steuerdokumente nach Paperless";
          After = [ "graphical-session.target" "network-online.target" ];
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${skript}/bin/tr-steuerdokumente";
        };
      };

      systemd.user.timers.tr-steuerdokumente = {
        Unit.Description = "Monatlich Trade-Republic-Steuerdokumente holen";
        Timer = {
          OnCalendar = "*-*-05 10:00";
          Persistent = true;
          RandomizedDelaySec = "1h";
        };
        Install.WantedBy = [ "timers.target" ];
      };
    };
}
