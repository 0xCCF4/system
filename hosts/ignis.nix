{ lib, pkgs, mine, config, ... }: with lib; {
  imports = [
    ../hardware/lenovoThinkpadL14amd.nix

    # Users
    ../users/mx.nix
  ] ++ mine.lib.optionalsIfExist [
    ../external/private/hosts/ignis.nix
  ];

  config = {
    # General settings
    networking.hostName = "ignis";
    mine.presets.primary = "workstation";
    networking.hostId = "cf5506f0";

    mine.persistence.enable = true;

    specialisation."no-persistence".configuration = {
      mine.persistence.enable = mkForce false;
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
