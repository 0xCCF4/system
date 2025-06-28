{ ... }: {
  imports = [
    ../hardware/netcup.nix

    # Users
    ../users/mx.nix
  ];

  config = {
    networking.hostName = "lux";
    mine.presets.primary = "server";
  };
}
