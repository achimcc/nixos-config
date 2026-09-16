# VPN in der GNOME-Sitzung: Leisten-Erweiterung, Tastenkürzel, Wechsel beim Login.
# Umgeschaltet wird immer über `vpn` (modules/vpn.nix).

{ lib, pkgs, ... }:

let
  uuid = "vpn-indikator@local";

  # Die Zustandslogik wird beim Bau getestet: ein roter Test macht den Bau rot.
  vpnIndikator = pkgs.runCommand "gnome-shell-extension-vpn-indikator"
    { nativeBuildInputs = [ pkgs.gjs ]; }
    ''
      export HOME=$TMPDIR
      gjs -m ${./vpn-indikator}/test-zustand.js
      ziel=$out/share/gnome-shell/extensions/${uuid}
      mkdir -p $ziel
      cp ${./vpn-indikator}/{metadata.json,extension.js,zustand.js,stylesheet.css} $ziel/
    '';

  ziffern = lib.range 0 9;
  pfad = n: "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/vpn${toString n}/";
in
{
  home.packages = [ vpnIndikator ];

  # Listen in dconf.settings werden über Module hinweg zusammengeführt
  # (gemessen 2026-09-13 an enabled-extensions aus home.nix + gnome-settings.nix).
  dconf.settings = {
    "org/gnome/shell".enabled-extensions = [ uuid ];
    "org/gnome/settings-daemon/plugins/media-keys".custom-keybindings = map pfad ziffern;
  } // lib.listToAttrs (map
    (n: lib.nameValuePair "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/vpn${toString n}" {
      # Super+Shift, nicht Super+Alt: das Layout us-umlaut macht die linke Alt zur
      # Umlaut-Ebene (nur Gruppe 1 definiert → gilt auch im de-Layout), im de-Layout ist
      # die rechte Alt AltGr — auf der ThinkPad-Tastatur gibt es also keine Alt-Taste.
      # Super+N ist App-Wechsel, Super+Strg+N neues App-Fenster, Super+Alt+8 die Lupe.
      name = if n == 0 then "VPN aus" else "VPN Slot ${toString n}";
      command = "/run/current-system/sw/bin/vpn ${if n == 0 then "aus" else toString n}";
      binding = "<Super><Shift>${toString n}";
    })
    ziffern);

  # Nach dem Login auf den zuletzt benutzten Slot (beim Boot verbindet vpn-boot Slot 1).
  systemd.user.services.vpn-login = {
    Unit = {
      Description = "VPN: nach dem Login auf den zuletzt benutzten Slot wechseln";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "/run/current-system/sw/bin/vpn login";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
