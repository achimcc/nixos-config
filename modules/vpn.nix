# WireGuard statt ProtonVPN-GUI: neun feste Proton-Server als NetworkManager-Profile.
# Spec: docs/superpowers/specs/2026-09-13-wireguard-statt-proton-gui-design.md
#
# Umgeschaltet wird nur über den Befehl `vpn` (Tastenkürzel, Leiste, Terminal).
# Die Serverliste kommt aus dem privaten Repo (Flake-Input identity), die privaten
# Schlüssel aus SOPS. Kein DNS in den Profilen: resolved behält das globale DoT
# (Quad9/Mullvad), die Anfragen laufen über die Default-Route durch den Tunnel.

{ config, lib, pkgs, id, vpnServer, ... }:

let
  slotName = s: "wg-${toString s.slot}";
  schluesselName = s: "wireguard/slot${toString s.slot}";
  envName = s: "WG${toString s.slot}_KEY";

  profil = s: lib.nameValuePair (slotName s) {
    connection = {
      id = slotName s;
      type = "wireguard";
      interface-name = slotName s;
      # Kein NM-Autoconnect: beim Boot verbindet vpn-boot.service Slot 1 genau einmal.
      autoconnect = false;
    };
    wireguard.private-key = "$" + envName s;
    "wireguard-peer.${s.serverPublicKey}" = {
      endpoint = "${s.endpoint}:${toString s.port}";
      allowed-ips = "0.0.0.0/0;";
      # Pflicht: ohne Verkehr handshaket WireGuard nicht, ein ruhender Tunnel sähe
      # sonst nach 180 s aus wie ein hängender.
      persistent-keepalive = 25;
    };
    ipv4 = {
      method = "manual";
      address1 = s.address;
    };
    ipv6.method = "disabled";
  };
in
{
  assertions = [
    {
      assertion = builtins.sort builtins.lessThan (map (s: s.slot) vpnServer) == lib.range 1 9;
      message = "vpn: Serverliste braucht genau die Slots 1–9 (identity/vpn/laptop.nix).";
    }
    {
      assertion = lib.all (s: builtins.match "[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+" s.endpoint != null) vpnServer;
      message = "vpn: endpoint muss eine IPv4-Adresse sein — die Firewall-Regel braucht IPs, keine Namen.";
    }
  ];

  boot.kernelModules = [ "wireguard" ];

  sops.secrets = lib.listToAttrs (map (s: lib.nameValuePair (schluesselName s) { }) vpnServer);

  sops.templates."nm-wireguard-env" = {
    content = lib.concatMapStrings
      (s: "${envName s}=${config.sops.placeholder.${schluesselName s}}\n")
      vpnServer;
    owner = "root";
    group = "root";
    mode = "0400";
  };

  networking.networkmanager.ensureProfiles = {
    environmentFiles = [ config.sops.templates."nm-wireguard-env".path ];
    profiles = lib.listToAttrs (map profil vpnServer);
  };

  # Namen für Leiste und Befehl — Slot und Anzeigename, nichts Geheimes.
  environment.etc."vpn/server.json".text =
    builtins.toJSON (map (s: { inherit (s) slot name; }) vpnServer);

  # Beim Boot einmal Slot 1 verbinden — sonst wären Dienste ohne Login
  # (Mail-Alarme, CVE-Monitor, Suricata-Updates) mit Kill-Switch ausgesperrt.
  systemd.services.vpn-boot = {
    description = "VPN: beim Boot mit Slot 1 verbinden";
    wantedBy = [ "multi-user.target" ];
    after = [ "NetworkManager.service" "NetworkManager-ensure-profiles.service" ];
    wants = [ "NetworkManager-ensure-profiles.service" ];
    # Ein nixos-rebuild soll einen laufenden Tunnel nicht umschalten.
    restartIfChanged = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.networkmanager}/bin/nmcli connection up wg-1";
    };
  };

  environment.systemPackages = [ pkgs.wireguard-tools ];
}
