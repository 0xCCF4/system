{ lib, pkgs, mine, ... }: with lib; {
  imports = [
    ../hardware/lenovoThinkpadL14amd.nix

    # Users
    ../users/mx.nix
  ] ++ mine.lib.optionalsIfExist [
    ../external/private/hosts/ignis.nix
  ];

  config = {
    networking.hostName = "ignis";
    mine.presets.primary = "workstation";

    # Battery management
    mine.tlp.enable = true;

    home-manager.users.mx = {
      config = {
        home.mine.traits.traits = [
          "development"
          "office"
        ];
        home.packages = with pkgs; [
          binaryWallpapers
        ];
      };
    };

    virtualisation.vmVariant = {
      # following configuration is added only when building VM with build-vm
      virtualisation = {
        memorySize = 4096;
        cores = 8;
      };
      users.users.mx.hashedPasswordFile = lib.mkForce null;
      users.users.mx.password = "mx";
    };
  };
}
