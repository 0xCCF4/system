{ lib, pkgs, mine, config, ... }: with lib; {
  imports = [
    ../hardware/lenovoThinkpadP14.nix

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

    mine.locale.keyboardLayout = "us";

    specialisation."de-keyboard".configuration = {
      mine.locale.keyboardLayout = mkForce "de";
    };

    # Battery management
    mine.tlp.enable = true;

    home-manager.users.mx = {
      config = {
        home.mine.traits.traits = [
          "development"
          "office"
        ];
        home.mine.slack.enable = true;
        services.gromit-mpx.enable = false;
      };
    };

    security.sudo.wheelNeedsPassword = mkIf config.age.rekey.initialRollout false;

    mine.desktop.hyprland.enable = true;
    mine.desktop.gnome.enable = true;
  };
}
