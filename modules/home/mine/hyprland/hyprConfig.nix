{ pkgs, lib, config, osConfig, ... }: with pkgs; with builtins; with lib; let
  waybar = "${config.programs.waybar.package}/bin/waybar";
  terminal = "${config.programs.kitty.package}/bin/kitty";
  fileManager = "nautilus";
  rofi = "${config.programs.rofi.package}/bin/rofi";
  lock = "${config.programs.hyprlock.package}/bin/hyprlock";
  hyprctl = "${if config.wayland.windowManager.hyprland.package != null then config.wayland.windowManager.hyprland.package else osConfig.programs.hyprland.package}/bin/hyprctl";
  portalPackage = if config.wayland.windowManager.hyprland.portalPackage != null then config.wayland.windowManager.hyprland.portalPackage else osConfig.programs.hyprland.portalPackage;
in
{
  wayland.windowManager.hyprland = {
    settings = {
      "$terminal" = "${terminal}";
      "$fileManager" = "${fileManager}";
      "$menu" = "${rofi} -show drun";
      "$reload_waybar" = "pkill waybar; ${waybar} &";
      "$lock" = "${lock}";
      "$hyprctl" = "${hyprctl}";

      "$mainMod" = "SUPER";

      input = {
        kb_layout = mkDefault osConfig.mine.locale.keyboardLayout;

        touchpad = {
          natural_scroll = mkDefault true;
        };
      };

      dwindle = {
        pseudotile = true;
        preserve_split = true;
      };

      master = {
        new_status = "master";
      };

      env = [
        "GTK_THEME,Tokyo-Night-Dark"
        "GTK_ICON_THEME,Adwaita"
        "XCURSOR_THEME,Adwaita"

        "XCURSOR_SIZE,24"
        "HYPRCURSOR_SIZE,24"
        "XDG_CURRENT_DESKTOP,Hyprland"
        "XDG_SESSION_TYPE,wayland"
      ];

      permission = [
        "${portalPackage}/bin/xdg-desktop-portal-hyprland, screencopy, allow"
      ];

      ecosystem = {
        no_update_news = true;
        no_donation_nag = true;
      };
    };
  };
}
