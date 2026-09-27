# hs-riegel — Signatur-Riegel fuer Homeserver-Deploys, ausserhalb des
# geprueften Repos (Begruendung im Kopf von hs-riegel.sh, Einbindung in
# modules/hs-riegel.nix, Test in test.sh als checks.x86_64-linux.hs-riegel).
{
  lib,
  runCommand,
  writeShellApplication,
  symlinkJoin,
  fetchurl,
  git,
  jq,
  gnupg,
  openssh,
  coreutils,
  gnugrep,
  gnused,
  gawk,
  gh,
  curl,
  python3,
}:

let
  # GitHubs Schluessel fuer Commits aus Weboberflaeche und API
  # (https://github.com/web-flow.gpg, am 2026-09-27 geholt). Die Datei traegt
  # zwei Schluessel:
  #   5DE3E0509C47EA3CF04A42D34AEE18F83AFDEB23  alt, abgelaufen 2024-01-16
  #   968479A1AFF927E37D1A566BB5690EEEBB952194  aktuell, seit 2024-01-16
  # Zugelassen wird NUR der aktuelle (webflowFpr) — ein abgelaufener Schluessel
  # ergibt ohnehin kein `G`. Aendert GitHub die Datei, bricht der Hash beim
  # naechsten Bau, nicht still.
  webflow = fetchurl {
    url = "https://github.com/web-flow.gpg";
    hash = "sha256-bor2h/YM8/QDFRyPsbJuleb55CTKYMyPN4e9RGaj74Q=";
  };
  webflowFpr = "968479A1AFF927E37D1A566BB5690EEEBB952194";
  webflowFprs = [
    "5DE3E0509C47EA3CF04A42D34AEE18F83AFDEB23"
    webflowFpr
  ];

  # Belegt beim Bau, dass die gepinnte Datei genau diese Fingerabdruecke traegt.
  webflowGeprueft = runCommand "web-flow-geprueft.gpg" { nativeBuildInputs = [ gnupg ]; } ''
    export GNUPGHOME=$(mktemp -d)
    ist=$(gpg --batch --show-keys --with-colons ${webflow} | grep '^pub' -A1 | grep '^fpr' | cut -d: -f10 | sort | tr '\n' ' ')
    soll="${lib.concatStringsSep " " (lib.sort (a: b: a < b) webflowFprs)} "
    if [ "$ist" != "$soll" ]; then
      echo "web-flow.gpg: Fingerabdruecke '$ist' statt '$soll'" >&2
      exit 1
    fi
    cp ${webflow} $out
  '';

  sshFilter = writeShellApplication {
    name = "hs-deploy-ssh-filter";
    runtimeInputs = [ gawk ];
    text = builtins.readFile ./ssh-filter.sh;
  };

  riegel = writeShellApplication {
    name = "hs-riegel";
    runtimeInputs = [
      git
      jq
      gnupg
      openssh
      coreutils
      gnugrep
      gnused
      gh
      curl
      python3
    ];
    # Die Befunde sammeln sich, statt beim ersten Fehlschlag abzubrechen —
    # jeder Exit-Code wird ausdruecklich ausgewertet (0/1/2).
    text = ''
      set +e
      webflow_schluessel_datei=${webflowGeprueft}
      webflow_fpr=${webflowFpr}
      inhalt_py=${./inhalt.py}
    ''
    + builtins.readFile ./hs-riegel.sh;
  };

  deploy = writeShellApplication {
    name = "hs-deploy";
    runtimeInputs = [
      riegel
      sshFilter
      git
      openssh
      coreutils
    ];
    text = ''
      set +e
    ''
    + builtins.readFile ./hs-deploy.sh;
  };
in
symlinkJoin {
  name = "hs-riegel";
  paths = [
    riegel
    deploy
    sshFilter
  ];
  passthru = {
    inherit riegel deploy sshFilter webflowFpr;
    testSkript = ./test.sh;
  };
  meta.description = "Signatur-Riegel fuer Homeserver-Deploys (hs-riegel, hs-deploy)";
}
