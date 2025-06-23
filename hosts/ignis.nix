{ ... }: {
  imports = [
    ../hardware/lenovoThinkpadL14amd.nix
    ../users/mx.nix
  ];

  config = {
    networking.hostName = "ignis";

    mine.presets.primary = "workstation";

    mine.virtualization = {
      flatpak = false;
      distrobox = false;
    };

    mine.tlp.enable = true;
  };
}
