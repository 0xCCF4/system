{ config, lib, ... }: with lib;
{
  config = {
    nix.gc = {
      automatic = mkDefault true;
      dates = "daily";
      options = "--delete-older-than 7d";
    };
  };
}
