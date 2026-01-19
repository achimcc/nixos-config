{
  description = "NixOS Konfiguration für user";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";

    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # LLM-Agents für Crush
    llm-agents.url = "github:numtide/llm-agents.nix";
  };

  outputs = { self, nixpkgs, home-manager, llm-agents, ... } @inputs:
    let
      system = "x86_64-linux";
      # Wir definieren pkgs hier einmal zentral
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        inherit system;
        # Hier geben wir die Inputs an alle Module weiter
        specialArgs = { inherit inputs llm-agents; };
        modules = [
          ./configuration.nix

          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            # Wichtig: llm-agents auch an Home Manager durchreichen
            home-manager.extraSpecialArgs = { inherit llm-agents; };
            home-manager.users.user = import ./home.nix;
          }
        ];
      };
    };
}
