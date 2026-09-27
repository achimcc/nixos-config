# hs-riegel — der Signatur-Riegel fuer Homeserver-Deploys, AUSSERHALB des
# geprueften Repos (Paket und Begruendung: pkgs/hs-riegel/, Test:
# checks.x86_64-linux.hs-riegel).
#
# WARUM ES DAS GIBT: ~/Projects/homeserver ist privat auf GitHub Free — kein
# Branch-Schutz, keine Pflicht zu Signaturen. Bis hierher pruefte
# `scripts/signaturen-pruefen.sh` IM Repo die Signaturen vor dem Aktivieren;
# ein Angreifer mit Push-Recht aendert es aber im selben Commit, den es pruefen
# soll. Der Pruefer liegt deshalb hier, und der Vertrauensanker
# (~/.ssh/allowed_signers, home.nix) ebenso.
#
# DREI TEILE, wie bei lotse.nix und caveat.nix:
#
#  1. `hs-riegel` und `hs-deploy` SYSTEMWEIT. `hs-deploy [server|vps] …` liest
#     den laufenden Stand, faehrt `hs-riegel pruefen` und startet erst dann
#     `just deploy` bzw. `just deploy-vps` im Repo.
#
#  2. Der PreToolUse-Hook fuer Claude Code: Er LEHNT ein Bash-Kommando AB, das
#     `just deploy`, `just deploy-vps`, `scripts/deploy.sh` oder `colmena apply`
#     enthaelt — der Weg ist `hs-deploy`, auch im lotse-Deploy-Slot
#     (`lotse run --class=deploy … -- bash -c '… && hs-deploy server'`). Alle
#     anderen Kommandos bekommen KEINE Entscheidung und laufen durch den
#     normalen Freigabeweg; der Hook erzwingt keine Rueckfrage und schreibt
#     nichts um (den Platz braucht lotse, s. caveat.nix).
#
#  3. GRENZE: Der Hook haelt Claude-Sitzungen an, nicht einen Menschen am
#     Terminal und nicht ein Skript, das `just deploy` selbst aufruft (etwa
#     `just wartung`). Fuer die bleibt der Pruefer im Repo — und der Hinweis in
#     der CLAUDE.md des homeserver-Repos.
#
# AKTIVIERUNGSSKRIPT STATT SYMLINK aus demselben Grund wie in lotse.nix:
# ~/.claude/settings.json schreibt Claude Code selbst. Genau EIN Eintrag,
# idempotent; eine Datei, die kein gueltiges JSON ist, bleibt unberuehrt.
# Hinter `claudeCaveatHook`, damit die drei Schreiber von `.hooks.*`
# nacheinander laufen.
{ pkgs, id, ... }:

let
  # /run/current-system statt des Store-Pfads, aus demselben Grund wie bei lotse.
  hook = builtins.toJSON {
    matcher = "Bash";
    hooks = [
      {
        type = "command";
        command = "/run/current-system/sw/bin/hs-riegel hook claude";
        timeout = 5;
      }
    ];
  };
in
{
  environment.systemPackages = [ pkgs.hs-riegel ];

  home-manager.users.${id.username} =
    { lib, ... }:
    {
      home.activation.claudeHsRiegelHook = lib.hm.dag.entryAfter [ "claudeCaveatHook" ] ''
        datei="$HOME/.claude/settings.json"
        if [ ! -e "$datei" ]; then
          run mkdir -p "$HOME/.claude"
          run sh -c 'printf "{}\n" > "$1"' _ "$datei"
        fi
        neu="$(${pkgs.coreutils}/bin/mktemp "$datei.XXXXXX")"
        if ${pkgs.jq}/bin/jq --argjson hook ${lib.escapeShellArg hook} '
              .hooks.PreToolUse = (
                ((.hooks.PreToolUse // [])
                  | map(select(
                      ((.hooks // []) | any((.command // "") | test("hs-riegel hook claude"))) | not
                    )))
                + [$hook]
              )
            ' "$datei" > "$neu"; then
          run ${pkgs.coreutils}/bin/chmod --reference="$datei" "$neu"
          run ${pkgs.coreutils}/bin/mv "$neu" "$datei"
        else
          ${pkgs.coreutils}/bin/rm -f "$neu"
          echo "hs-riegel: $datei ist kein gueltiges JSON — der Hook wurde NICHT eingetragen." >&2
        fi
      '';
    };
}
