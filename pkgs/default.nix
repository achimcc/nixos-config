# Custom packages overlay
{ pkgs }:

{
  shadow-simulator = pkgs.callPackage ./shadow { };
  hs-riegel = pkgs.callPackage ./hs-riegel { };
}
