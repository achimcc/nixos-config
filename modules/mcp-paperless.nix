# Paperless-MCP fuer Claude Code — das Papierarchiv des Homeservers
# (papiere.rusty-vault.de) ueber dessen REST-API. 2026-10-11 auf Achims
# Wunsch, global. Paket: pkgs/paperless-ngx-mcp.
#
# WAS DAS WERKZEUG DARF, bevor man es benutzt: ALLES. Der Token gehoert Achims
# eigenem Konto (Superuser in Paperless), auf seine Entscheidung. Upstream
# bietet ueber 100 Werkzeuge, darunter Dokumente, Schlagworte und
# Korrespondenten loeschen, `bulk_edit`, Arbeitsablaeufe und Mailkonten
# aendern, den Papierkorb leeren und Dateien hochladen (`document_upload` liest
# JEDEN Pfad, den der Nutzer lesen kann). Und jedes Ergebnis landet roh im
# Chat, an gestalt vorbei — auch der OCR-Text von Steuer- und Arztpapieren.
#
# DER TOKEN HAT GENAU EINE QUELLE: `paperless-mcp-token` in
# ~/Projects/homeserver-secrets/secrets/papier.yaml. Die Unit
# `paperless-verwalter` auf papier-01 schreibt ihn in Paperless' Datenbank
# (homeserver, hosts/server/gaeste/papier-01.nix); der Wrapper hier
# entschluesselt ihn beim ersten Start per sops (TPM-Identitaet) und legt ihn
# unter $XDG_RUNTIME_DIR ab (tmpfs, 0700) — dieselbe Bauart wie
# grafana-mcp-homeserver. Eine zweite Kopie in secrets/secrets.yaml dieses
# Repos gibt es mit Absicht nicht: zwei Kopien laufen bei einer Rotation
# auseinander.
#
# Antwortet Paperless mit 401 (rotiert, oder in der Oberflaeche ein neuer
# Token erzeugt — DRF kennt nur einen je Konto), entschluesselt der Wrapper
# neu. Hilft das nicht, steht der sops-Wert noch nicht in Paperless: Deploy
# des Homeservers abwarten oder `systemctl -M papier-01 restart
# paperless-verwalter` auf dem Server.
#
# TEMPORAERE DOWNLOADS: Der Server legt je Prozess ein Verzeichnis unter
# $TMPDIR an und loescht es beim Beenden. TMPDIR zeigt deshalb ebenfalls in
# den Laufzeitordner — Dokumente liegen so nie auf der Platte.
{ pkgs, id, ... }:

let
  wrapper = pkgs.writeShellApplication {
    name = "paperless-mcp-homeserver";
    runtimeInputs = with pkgs; [ curl sops util-linux coreutils gnugrep ];
    text = ''
      geheim=''${HOMESERVER_SECRETS:-$HOME/Projects/homeserver-secrets}
      url=https://papiere.rusty-vault.de
      dir="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/paperless-mcp"
      umask 077
      mkdir -p "$dir/tmp"
      token="$dir/token"

      # stdout ist der MCP-Kanal: jede Meldung geht nach stderr.
      antwort() {
        # Der Kopf geht ueber eine Datei, nicht argv.
        kopf="$dir/kopf.$$"
        printf 'Authorization: Token %s\n' "$(cat "$token")" > "$kopf"
        curl -s -o /dev/null -w '%{http_code}' --max-time 10 -H @"$kopf" \
          "$url/api/tags/?page_size=1" || true
        rm -f "$kopf"
      }

      entschluesseln() {
        if [ ! -r "$geheim/secrets/papier.yaml" ]; then
          echo "paperless-mcp: $geheim/secrets/papier.yaml fehlt." >&2
          return 1
        fi
        sops -d --extract '["paperless-mcp-token"]' "$geheim/secrets/papier.yaml" \
          | tr -d '\n' > "$token.neu"
        if ! grep -qE '^[0-9a-f]{40}$' "$token.neu"; then
          rm -f "$token.neu"
          echo "paperless-mcp: paperless-mcp-token fehlt in papier.yaml oder hat nicht die Form eines DRF-Tokens." >&2
          return 1
        fi
        mv "$token.neu" "$token"
      }

      (
        flock 9
        [ -s "$token" ] || entschluesseln
        code=$(antwort)
        if [ "$code" = 401 ] || [ "$code" = 403 ]; then
          entschluesseln
          code=$(antwort)
        fi
        case "$code" in
          200) ;;
          000) echo "paperless-mcp: $url nicht erreichbar (Netz, DNS?)." >&2; exit 1 ;;
          401|403) echo "paperless-mcp: Paperless lehnt den Token ab ($code) — steht der sops-Wert schon in Paperless? (paperless-verwalter auf papier-01)" >&2; exit 1 ;;
          *) echo "paperless-mcp: $url/api antwortete $code." >&2; exit 1 ;;
        esac
      ) 9>"$dir/sperre"

      PAPERLESS_URL=$url
      PAPERLESS_TOKEN=$(cat "$token")
      TMPDIR="$dir/tmp"
      export PAPERLESS_URL PAPERLESS_TOKEN TMPDIR
      exec ${pkgs.paperless-ngx-mcp}/bin/paperless-ngx-mcp mcp "$@"
    '';
  };

  # Pfad ueber /run/current-system statt Store-Pfad — Begruendung in
  # modules/mcp-nixos.nix.
  server = builtins.toJSON {
    type = "stdio";
    command = "/run/current-system/sw/bin/paperless-mcp-homeserver";
    args = [ ];
    env = { };
  };
in
{
  environment.systemPackages = [ wrapper ];

  home-manager.users.${id.username} =
    { lib, ... }:
    {
      # Server in ~/.claude.json (user scope, s. mcp-nixos.nix). Idempotent;
      # eine Datei, die kein gueltiges JSON ist, bleibt unberuehrt.
      home.activation.claudeMcpPaperless = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        datei="$HOME/.claude.json"
        if [ ! -e "$datei" ]; then
          run sh -c 'printf "{}\n" > "$1"' _ "$datei"
          run ${pkgs.coreutils}/bin/chmod 600 "$datei"
        fi
        neu="$(${pkgs.coreutils}/bin/mktemp "$datei.XXXXXX")"
        if ${pkgs.jq}/bin/jq --argjson server ${lib.escapeShellArg server} '
              .mcpServers = ((.mcpServers // {}) + { paperless: $server })
            ' "$datei" > "$neu"; then
          run ${pkgs.coreutils}/bin/chmod --reference="$datei" "$neu"
          run ${pkgs.coreutils}/bin/mv "$neu" "$datei"
        else
          ${pkgs.coreutils}/bin/rm -f "$neu"
          echo "mcp-paperless: $datei ist kein gueltiges JSON — der Server wurde NICHT eingetragen." >&2
        fi
      '';
    };
}
