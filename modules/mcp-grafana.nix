# Grafana-MCP fuer Claude Code, nur im homeserver-Repo (2026-09-28).
#
# WOZU: Prometheus-Abfragen, Alarmregeln und Dashboards von obs-01 direkt
# lesen, statt jede Frage als ssh + curl + gestalt zu bauen.
#
# WAS DER SERVER SIEHT, UND WAS NICHT: Ein MCP-Ergebnis landet ROH im Chat,
# an gestalt vorbei. Metriken tragen hier keine Geheimnisse, Logzeilen schon
# (leakwatch hat Schluessel in Journalen gefunden). Deshalb:
#   --disable-loki, --disable-runpanelquery  keine Logzeilen, auch nicht ueber
#                                            ein Panel mit Loki-Abfrage
#   --disable-write                          nichts anlegen oder aendern
#   --disable-admin, …                       nur, was hier gebraucht wird
# Und das Konto ist ein Service-Account mit Rolle VIEWER, nicht admin.
#
# DER TOKEN LEBT 12 STUNDEN und steht nirgends auf der Platte ausser unter
# $XDG_RUNTIME_DIR (tmpfs, 0700). Grafana kann keinen Token mit vorgegebenem
# Wert annehmen — ein sops-Secret geht also nicht. Stattdessen legt der
# Wrapper beim Start, falls noetig, den Token selbst an: Anmeldung als admin
# ueber das FORMULAR (Basic Auth ist auf obs-01 aus), Passwort aus
# homeserver-secrets per sops, Rumpf ueber eine Datei statt argv — dieselbe
# Bauart wie der Konten-Nachlauf in obs-01.nix. Abgelaufene Tokens des
# Kontos raeumt er dabei ab.
#
# Mehrere Sitzungen nebeneinander teilen sich den Token (flock), der Tunnel
# ist derselbe wie bei `just crosshair` (scripts/grafana-tunnel.sh).
#
# EINGETRAGEN wird der Server nicht hier, sondern in `.mcp.json` des
# homeserver-Repos (project scope): Er soll nur dort starten, wo es um den
# Homeserver geht, und in jedem Worktree.
{ pkgs, ... }:

let
  wrapper = pkgs.writeShellApplication {
    name = "grafana-mcp-homeserver";
    runtimeInputs = with pkgs; [ curl jq sops git openssh util-linux coreutils procps ];
    text = ''
      repo=''${HOMESERVER_REPO:-$HOME/Projects/homeserver}
      api=http://127.0.0.1:3000
      konto=claude-mcp
      laufzeit=43200   # 12 h
      dir="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/grafana-mcp"
      umask 077
      mkdir -p "$dir"
      token="$dir/token"
      ablauf="$dir/ablauf"

      # Der Tunnel meldet sich auf stdout — das ist hier der MCP-Kanal.
      "$repo/scripts/grafana-tunnel.sh" auf >&2 || {
        echo "grafana-mcp: kein Tunnel zu obs-01." >&2; exit 1; }

      gueltig() {
        [ -s "$token" ] && [ -s "$ablauf" ] || return 1
        [ "$(date +%s)" -lt "$(( $(cat "$ablauf") - 3600 ))" ] || return 1
        # Ein Token, den Grafana nicht mehr kennt (geloescht, Neuinstallation),
        # faellt hier auf. Der Kopf geht ueber eine Datei, nicht argv.
        kopf="$dir/kopf.$$"
        printf 'Authorization: Bearer %s\n' "$(cat "$token")" > "$kopf"
        code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -H @"$kopf" "$api/api/user")
        rm -f "$kopf"
        [ "$code" = 200 ]
      }

      neu_anlegen() {
        arbeit=$(mktemp -d "$dir/lauf.XXXXXX")
        trap 'rm -rf "$arbeit"' RETURN
        geheim=$("$repo/scripts/geheim-pfad.sh" "$repo")
        sops -d --extract '["grafana-admin-password"]' "$geheim/secrets/obs.yaml" > "$arbeit/pw"
        jq -nc --rawfile p "$arbeit/pw" '{user:"admin", password:($p|rtrimstr("\n"))}' > "$arbeit/rumpf"
        rm -f "$arbeit/pw"
        curl -sS --max-time 15 -c "$arbeit/keks" -X POST "$api/login" \
             -H 'Content-Type: application/json' --data @"$arbeit/rumpf" \
          | jq -e '.message == "Logged in"' >/dev/null || {
            echo "grafana-mcp: Anmeldung als admin scheiterte." >&2; return 1; }
        rm -f "$arbeit/rumpf"

        sa=$(curl -sS --max-time 10 -b "$arbeit/keks" "$api/api/serviceaccounts/search?query=$konto" \
          | jq -r --arg k "$konto" '.serviceAccounts[] | select(.name == $k) | .id' | head -1)
        if [ -z "$sa" ]; then
          sa=$(curl -sS --max-time 10 -b "$arbeit/keks" -X POST "$api/api/serviceaccounts" \
                 -H 'Content-Type: application/json' \
                 --data "{\"name\":\"$konto\",\"role\":\"Viewer\",\"isDisabled\":false}" \
               | jq -r '.id // empty')
          [ -n "$sa" ] || { echo "grafana-mcp: Service-Account liess sich nicht anlegen." >&2; return 1; }
        fi

        # Abgelaufene Tokens des Kontos abraeumen — sonst waechst die Liste
        # mit jeder Sitzung.
        curl -sS --max-time 10 -b "$arbeit/keks" "$api/api/serviceaccounts/$sa/tokens" \
          | jq -r '.[] | select(.hasExpired == true) | .id' \
          | while read -r alt; do
              curl -sS -o /dev/null --max-time 10 -b "$arbeit/keks" -X DELETE \
                "$api/api/serviceaccounts/$sa/tokens/$alt"
            done

        curl -sS --max-time 10 -b "$arbeit/keks" -X POST "$api/api/serviceaccounts/$sa/tokens" \
             -H 'Content-Type: application/json' \
             --data "{\"name\":\"mcp-$(date +%Y%m%d-%H%M%S)\",\"secondsToLive\":$laufzeit}" \
          | jq -r '.key // empty' > "$token.neu"
        [ -s "$token.neu" ] || { rm -f "$token.neu"; echo "grafana-mcp: kein Token erhalten." >&2; return 1; }
        mv "$token.neu" "$token"
        echo $(( $(date +%s) + laufzeit )) > "$ablauf"
      }

      (
        flock 9
        gueltig || neu_anlegen
      ) 9>"$dir/sperre"

      [ -s "$token" ] || exit 1
      GRAFANA_URL=$api
      GRAFANA_SERVICE_ACCOUNT_TOKEN=$(cat "$token")
      export GRAFANA_URL GRAFANA_SERVICE_ACCOUNT_TOKEN
      exec ${pkgs.mcp-grafana}/bin/mcp-grafana \
        --disable-write \
        --disable-loki \
        --disable-runpanelquery \
        --disable-admin \
        --disable-oncall \
        --disable-incident \
        --disable-sift \
        --disable-asserts \
        --disable-pyroscope \
        --disable-elasticsearch \
        --disable-quickwit \
        --disable-influxdb \
        --disable-cloudwatch \
        --disable-sql \
        --disable-graphite \
        --disable-rendering \
        --disable-snapshot \
        --disable-provisioning \
        --disable-agento11y \
        --disable-assistant \
        "$@"
    '';
  };
in
{
  environment.systemPackages = [ wrapper ];
}
