# Custom packages overlay
{ pkgs }:

{
  shadow-simulator = pkgs.callPackage ./shadow { };
  moonfin = pkgs.callPackage ./moonfin { };
}
