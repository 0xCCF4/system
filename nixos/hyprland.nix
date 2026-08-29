{ lib, config, pkgs, ... }: with lib;
{
  options.mine.desktop.hyprland = with types; {
    enable = mkOption {
      type = bool;
      default = false;
      description = "Enable Hyprland desktop environment.";
    };
  };

  config = mkIf config.mine.desktop.hyprland.enable {
    programs.hyprland.enable = mkDefault true;
    programs.hyprlock.enable = mkDefault true;

    xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

    xdg.portal.config.hyprland = {
      default = [ "hyprland" "gtk" ];
      "org.freedesktop.impl.portal.FileChooser" = "gtk";
    };
  };
}
