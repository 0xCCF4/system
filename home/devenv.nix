{ config
, pkgs
, lib
, self
, osConfig
, ...
}:
with lib;
{
  config = {
    #programs.devenv.enable = mkDefault true;
  };
}
