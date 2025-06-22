{ inputs
, pkgs
, lib
, config
, ...
}:
with lib;
{
  nixpkgs.hostPlatform = mkDefault "x86_64-linux";
}
