{
  description = "NixOS Konfiguration für Achim";

  inputs = {
    # NixOS 24.11 stable
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";

    # Home Manager passend zu NixOS 24.11
    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # NUR für Crush (AI Coding Assistant)
    nur.url = "github:nix-community/NUR";
  };

  outputs = { self, nixpkgs, home-manager, nur, ... }:
    let
      system = "x86_64-linux";
      pkgsWithUnfree = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      nurPkgs = import nur {
        nurpkgs = pkgsWithUnfree;
        pkgs = pkgsWithUnfree;
      };
    in
    {
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ./configuration.nix

          # Home Manager als NixOS Modul
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit nurPkgs; };
            home-manager.users.achim = import ./home-achim.nix;
          }
        ];
      };
    };
}
