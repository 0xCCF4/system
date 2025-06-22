{ ... }: {
  imports = [
    ../hardware/netcup.nix
  ];

  config.networking.hostName = "lux";
}
