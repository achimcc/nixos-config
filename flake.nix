{
  description = "NixOS Konfiguration für Achim";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # LLM-Agents für Crush
    llm-agents.url = "github:numtide/llm-agents.nix";

    # Sops-nix für verschlüsselte Secrets
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Lanzaboote für Secure Boot
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v0.4.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Deklaratives Flatpak
    nix-flatpak.url = "github:gmodena/nix-flatpak";
  };

  outputs = { self, nixpkgs, home-manager, llm-agents, sops-nix, lanzaboote, nix-flatpak, ... } @inputs:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations.achim-laptop = nixpkgs.lib.nixosSystem {
        inherit system;
        # Hier geben wir die Inputs an alle Module weiter
        specialArgs = { inherit inputs llm-agents; };
        modules = [
          ./configuration.nix

          # Sops-nix Modul
          sops-nix.nixosModules.sops

          # Lanzaboote für Secure Boot
          lanzaboote.nixosModules.lanzaboote

          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            # Wichtig: llm-agents auch an Home Manager durchreichen
            home-manager.extraSpecialArgs = { inherit llm-agents; };
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
