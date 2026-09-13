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

  vpnStatus = pkgs.writeShellApplication {
    name = "vpn-status";
    runtimeInputs = with pkgs; [ wireguard-tools nftables jq gnugrep gawk coreutils ];
    text = builtins.readFile ./vpn/vpn-status.sh;
  };

  # Füllt die Chain `direkt` (firewall.nix). Fremdes DoT/DoQ bleibt auch ungeschützt
  # gesperrt; erlaubt sind nur die resolved-Server Quad9 und Mullvad.
  direktAn = pkgs.writeShellScript "vpn-direkt-an" ''
    ${pkgs.nftables}/bin/nft -f - <<'EOF'
    flush chain inet filter direkt
    add rule inet filter direkt meta l4proto { tcp, udp } th dport 853 ip daddr != { 9.9.9.9, 194.242.2.2 } drop
    add rule inet filter direkt accept
    EOF
  '';

  vpnBefehl = pkgs.writeShellApplication {
    name = "vpn";
    runtimeInputs = with pkgs; [ networkmanager jq curl util-linux libnotify systemd coreutils gawk ];
    text = builtins.readFile ./vpn/vpn.sh;
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

  systemd.services.vpn-status = {
    description = "VPN: Zustand messen und nach /run/vpn/status.json schreiben";
    wantedBy = [ "multi-user.target" ];
    after = [ "nftables.service" ];
    serviceConfig = {
      ExecStart = "${vpnStatus}/bin/vpn-status";
      Restart = "always";
      RestartSec = "2s";
      RuntimeDirectory = "vpn";
      RuntimeDirectoryMode = "0755";
      UMask = "0022";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
    };
  };

  # Zustand "Direkt": Kill-Switch bewusst aus, z. B. für Captive Portals.
  # Kein wantedBy → nach einem Neustart nie aktiv. Ein nftables-Reload leert die
  # Chain ohnehin; `vpn direkt` benutzt deshalb restart, nicht start.
  systemd.services.vpn-direkt = {
    description = "VPN: Kill-Switch bewusst aus (Zustand Direkt)";
    after = [ "nftables.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = direktAn;
      ExecStop = "${pkgs.nftables}/bin/nft flush chain inet filter direkt";
    };
  };

  # Der Nutzer darf genau vpn-direkt.service starten, stoppen, neu starten — nur in
  # der aktiven lokalen Sitzung und ohne Passwort. Sonst nichts an systemd.
  security.polkit.extraConfig = ''
    polkit.addRule(function (action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          action.lookup("unit") == "vpn-direkt.service" &&
          ["start", "stop", "restart"].indexOf(action.lookup("verb")) >= 0 &&
          subject.user == "${id.username}" && subject.local && subject.active) {
        return polkit.Result.YES;
      }
    });
  '';

  environment.systemPackages = [ pkgs.wireguard-tools vpnBefehl ];
}
