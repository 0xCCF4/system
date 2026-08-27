{ config, lib, ... }: with lib;
{
  config = {
    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];

    systemd.services.nix-daemon.environment.NIX_CURL_FLAGS = "-A Nix/${config.nix.package.version}";

    users.mutableUsers = mkDefault false;

    system.stateVersion = mkDefault "25.11";
  };
}
