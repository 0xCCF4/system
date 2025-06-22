{ ... }: {
  imports = [
    ../hardware/vps.nix
  ];

  config.networking.hostName = "lux";
}
