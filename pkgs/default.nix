# Custom packages overlay
{ pkgs }:

{
  shadow-simulator = pkgs.callPackage ./shadow { };
}
