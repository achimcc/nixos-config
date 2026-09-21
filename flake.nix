{
  description = "NixOS Konfiguration für ein ThinkPad T14 Gen 5";

  inputs = {
    # nixos-unstable Channel (voller Jobset).
    # GEÄNDERT 2026-06-24: von nixos-unstable-small auf nixos-unstable.
    # Grund: "-small" hat einen REDUZIERTEN Hydra-Jobset (v.a. Server-/Kernpakete).
    # Desktop-/GUI-Pakete liegen außerhalb → kein Binär-Cache-Treffer → Source-Build.
    # Bei einem Toolchain-Bump (gcc/rustc/stdenv) baut dann sehr viel aus Quellcode
    # (24.06. stundenlanger Build). Der volle "nixos-unstable"-Branch springt erst
    # weiter, nachdem Hydra praktisch ALLES gebaut hat → deutlich bessere Cache-
    # Treffer auf dem Desktop. Trade-off: Branch springt etwas langsamer.
    # (Früher temporär auf 70bcfff gepinnt für apparmor/PAM-Fix PR #511479,
    # gemergt 2026-04-19 — längst im Channel, Pin 2026-06-08 entfernt.)
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # master = neueste HM-Version (26.11), passend zur nixos-unstable
    # nixpkgs (ebenfalls 26.11 seit dem Release-Bump). follows nixpkgs hält beide
    # synchron → keine Versions-Mismatch-Warnung.
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # LLM-Agents für Crush
    llm-agents.url = "github:numtide/llm-agents.nix";

    # Sops-nix für verschlüsselte Secrets (gepinnt auf geprüften Commit)
    sops-nix = {
      url = "github:Mic92/sops-nix";
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

    # gestalt - JSON-Form ohne Werte (modules/gestalt.nix). Auf den TAG gepinnt:
    # ein Zweig liefe bei jedem `flake update` still weiter.
    gestalt = {
      url = "github:achimcc/gestalt/v0.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # lotse - Koordination der parallelen Claude-Code-Sitzungen: Auswertungen
    # anstellen statt den Speicher zu fuellen, dazu der PreToolUse-Hook
    # (modules/lotse.nix). Auf den TAG gepinnt wie gestalt.
    lotse = {
      url = "github:achimcc/lotse/v0.2.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # caveat - blendet die Lehre aus caveats/ ein, wenn ihr Meldungstext auftaucht
    # (modules/caveat.nix). Auf den TAG gepinnt wie lotse.
    caveat = {
      url = "github:achimcc/caveat/v0.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # mcp-nixos - MCP-Server mit echten NixOS-Daten statt erfundener Paketnamen
    # (modules/mcp-nixos.nix). Auf den TAG gepinnt wie gestalt und lotse: ein
    # Zweig liefe bei jedem `flake update` still weiter.
    mcp-nixos = {
      url = "github:utensils/mcp-nixos/v3.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Identität des Rechners (Username, Klarname, Mailadresse) aus dem PRIVATEN
    # Repo. Diese Werte werden zur BAUZEIT gebraucht — users.users.<name>,
    # /home/<name>/… und die Mailadresse stehen im Nix-Ausdruck selbst.
    # SOPS scheidet dafür aus: sops-nix entschlüsselt erst zur LAUFZEIT auf dem
    # Ziel und käme zu spät. `flake = false`, weil das Repo keine flake.nix hat.
    #
    # Preis, den man kennen muss: `sudo nixos-rebuild` kann diesen Input nicht
    # selbst holen — root hat den SSH-Schlüssel nicht. Nach einem
    # `nix-collect-garbage` deshalb erst als Nutzer `nix flake update identity`
    # und danach der übliche Rebuild.
    identity = {
      url = "git+ssh://git@github.com/achimcc/homeserver-secrets.git";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, llm-agents, sops-nix, lanzaboote, nix-flatpak, rcu, identity, ... } @inputs:
    let
      system = "x86_64-linux";

      # Identität aus dem privaten Repo: { username, realName, email }.
      id = import "${identity}/identity/laptop.nix";

      # WireGuard-Serverliste aus dem PRIVATEN Repo (Slots 1–9). Bauzeit-Daten:
      # NM-Profile und die Firewall-Regel für die Endpunkte brauchen sie, bevor
      # sops-nix irgendetwas entschlüsselt. Schlüssel liegen in secrets.yaml.
      vpnServer = import "${identity}/vpn/laptop.nix";

      # Unstable nixpkgs
      pkgs-unstable = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
      
      # Custom packages overlay
      customOverlay = final: prev: import ./pkgs { pkgs = prev; };

    in
    {
      # NixOS configuration name MUST match networking.hostName in network.nix
      # Otherwise nixos-rebuild will fail to find the configuration
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        inherit system;
        # Hier geben wir die Inputs an alle Module weiter
        specialArgs = { inherit inputs llm-agents pkgs-unstable id vpnServer; };
        modules = [
          # Custom packages overlay
          { nixpkgs.overlays = [ customOverlay ]; }
          
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
            home-manager.extraSpecialArgs = { inherit llm-agents pkgs-unstable rcu id vpnServer; };
            home-manager.users.${id.username} = import ./home.nix;
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
