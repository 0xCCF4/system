{ ... }: {
  imports = [
    ../hardware/netcup.nix
    ../users/mx.nix
  ];

  config = {
    networking.hostName = "lux";

    mine.presets.primary = "server";
  };
}
