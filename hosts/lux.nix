{ ... }: {
  imports = [
    ../hardware/vps.nix
    ../users/mx.nix
  ];

  config = {
    networking.hostName = "lux";

    mine.presets.primary = "server";
  };
}
