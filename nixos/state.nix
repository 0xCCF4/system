{ lib, ... }: with lib; {
  config = {
    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];

    users.mutableUsers = mkDefault false;

    system.stateVersion = mkDefault "25.11";
  };
}
