{ ... }: {
  imports = [
    ../hardware/lenovoThinkpadL14amd.nix
  ];

  config.networking.hostName = "ignis";
}
