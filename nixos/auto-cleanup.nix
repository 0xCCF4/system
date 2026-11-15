{ config, lib, ... }: with lib;
{
  config = {
    nix.gc = {
      automatic = mkDefault true;
      dates = "daily";
      options = "--delete-older-than 7d";
    };
    nix.optimise = {
      automatic = mkDefault true;
      dates = [ "weekly" ];
    };
  };
}
