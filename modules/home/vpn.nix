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
      name = if n == 0 then "VPN aus" else "VPN Slot ${toString n}";
      command = "/run/current-system/sw/bin/vpn ${if n == 0 then "aus" else toString n}";
      binding = "<Super><Alt>${toString n}";
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
