{ ... }: {
  imports = [
    ../hardware/vps.nix

    # Users
    ../users/mx.nix
  ];

  config = {
    networking.hostName = "lux";
    mine.presets.primary = "server";
  };
}
