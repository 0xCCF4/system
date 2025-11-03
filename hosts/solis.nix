{ lib, pkgs, mine, config, ... }: with lib; {
  imports = [
    ../hardware/lenovoThinkpadL14amd.nix

    # Users
    ../users/mx.nix
  ] ++ mine.lib.optionalsIfExist [
    ../external/private/hosts/solis.nix
  ];

  config = {
    # General settings
    networking.hostName = "solis";
    mine.presets.primary = "workstation";
    networking.hostId = "57c565f7";

    mine.persistence.enable = true;

    specialisation."no-store-sign".configuration = {
      mine.storeSign.enable = mkForce false;
    };

    # Battery management
    mine.tlp.enable = true;

    home-manager.users.mx = {
      config = {
        home.mine.traits.traits = [
          "development"
          "office"
        ];
      };
    };

    security.sudo.wheelNeedsPassword = mkIf config.age.rekey.initialRollout false;

    mine.desktop.hyprland.enable = true;
    mine.desktop.gnome.enable = mkForce false;
  };
}
