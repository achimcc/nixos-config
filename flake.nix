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
