{
  description = "NixOS Konfiguration für Achim";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # LLM-Agents für Crush
    llm-agents.url = "github:numtide/llm-agents.nix";

    # Sops-nix für verschlüsselte Secrets (gepinnt auf geprüften Commit)
    sops-nix = {
      url = "github:Mic92/sops-nix/5e8fae80726b66e9fec023d21cd3b3e638597aa9";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Lanzaboote für Secure Boot
    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Deklaratives Flatpak
    nix-flatpak.url = "github:gmodena/nix-flatpak";

    # RCU - reMarkable Connection Utility (gepinnt auf geprüften Commit)
    rcu.url = "git+https://github.com/thozza/rcu.git?rev=0dc42d188af723569a07f827b43713e9c56ef6c7";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, llm-agents, sops-nix, lanzaboote, nix-flatpak, rcu, ... } @inputs:
    let
      system = "x86_64-linux";
      
      # Unstable nixpkgs
      pkgs-unstable = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
      
      # Custom packages overlay
      customOverlay = final: prev: import ./pkgs { pkgs = prev; };

      # ProtonVPN Kill Switch Fix (systemd-resolved 258 + IPv6 disabled)
      # PROBLEM: ProtonVPN GUI aktiviert IMMER den Kill Switch beim Verbinden
      # (auch bei killswitch=0). Der WireGuard Kill Switch erstellt eine
      # NM-Dummy-Verbindung mit DNS 0.0.0.0 (von resolved 258 abgelehnt)
      # und IPv6-Config (scheitert bei kernel IPv6 disable). Beides zusammen
      # → add_connection_async hängt → 10s TimeoutError → kein VPN.
      # FIX: DNS auf gültige Adresse ändern + IPv6 im Kill Switch deaktivieren.
      protonvpnFixOverlay = final: prev: {
        pythonPackagesExtensions = (prev.pythonPackagesExtensions or []) ++ [
          (pyfinal: pyprev: {
            proton-vpn-api-core = pyprev.proton-vpn-api-core.overridePythonAttrs (old: {
              postPatch = (old.postPatch or "") + ''
                # Fix 1: DNS 0.0.0.0 → 100.85.0.1 (Kill Switch Gateway)
                # systemd-resolved 258 lehnt 0.0.0.0 als ungültige DNS-Adresse ab
                substituteInPlace proton/vpn/backend/networkmanager/killswitch/wireguard/killswitch_connection_handler.py \
                  --replace-fail 'dns=["0.0.0.0"]' 'dns=["100.85.0.1"]'
                substituteInPlace proton/vpn/backend/networkmanager/killswitch/default/killswitch_connection_handler.py \
                  --replace-fail 'dns=["0.0.0.0"]' 'dns=["100.85.0.1"]'

                # Fix 2: IPv6 im Kill Switch deaktivieren
                # IPv6 ist auf Kernel-Ebene deaktiviert (net.ipv6.conf.all.disable_ipv6=1)
                # → NM kann keine IPv6-Adressen/Routen auf dem Dummy-Interface konfigurieren
                # → Verbindungsaktivierung hängt endlos
                substituteInPlace proton/vpn/backend/networkmanager/killswitch/wireguard/killswitch_connection_handler.py \
                  --replace-fail 'ipv6_settings=self._ipv6_ks_settings,' 'ipv6_settings=None,'
                substituteInPlace proton/vpn/backend/networkmanager/killswitch/default/killswitch_connection_handler.py \
                  --replace-fail 'ipv6_settings=self._ipv6_ks_settings,' 'ipv6_settings=None,'
              '';
            });
          })
        ];
      };
    in
    {
      # NixOS configuration name MUST match networking.hostName in network.nix
      # Otherwise nixos-rebuild will fail to find the configuration
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        inherit system;
        # Hier geben wir die Inputs an alle Module weiter
        specialArgs = { inherit inputs llm-agents pkgs-unstable; };
        modules = [
          # Custom packages overlay
          { nixpkgs.overlays = [ customOverlay protonvpnFixOverlay ]; }
          
          ./configuration.nix

          # Sops-nix Modul
          sops-nix.nixosModules.sops

          # Lanzaboote für Secure Boot
          lanzaboote.nixosModules.lanzaboote

          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            # Wichtig: llm-agents und pkgs-unstable an Home Manager durchreichen
            home-manager.extraSpecialArgs = { inherit llm-agents pkgs-unstable rcu; };
            home-manager.users.achim = import ./home-achim.nix;
            # Sops für Home Manager
            home-manager.sharedModules = [
              sops-nix.homeManagerModules.sops
              nix-flatpak.homeManagerModules.nix-flatpak
            ];
          }
        ];
      };
    };
}
