{ config
, pkgs
, lib
, self
, osConfig
, ...
}:
with lib; with builtins;
{
  imports = [
    ./traits.nix
  ];

  config = {
    programs.zed-editor = {
      enable = mkDefault true;

      installRemoteServer = true;
    };
  };
}
