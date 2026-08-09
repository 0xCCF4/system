{ config, lib, ... }: with lib; {
  config = mkIf cfg.enable {
    nix.gc = {
      automatic = mkDefault true;
      dates = "daily";
      options = "--delete-older-than 7d";
    };
  };
}
