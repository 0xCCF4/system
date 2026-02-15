{ config
, pkgs
, lib
, osConfig
, ...
}:
with lib; with builtins;
{
  imports = [
    ./traits.nix
  ];

  config = {
    programs.zathura = {
      enable = mkDefault config.home.mine.traits.hasOffice;
    };
  };
}
