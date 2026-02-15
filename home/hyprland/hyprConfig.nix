{ pkgs, lib, config, osConfig, ... }: with pkgs; with builtins; with lib; let
  waybar = "${getExe config.programs.waybar.package}";
  terminal = "${getExe config.programs.kitty.package}";
  fileManager = "nautilus";
  rofi = "${getExe config.programs.rofi.package}";
  lock = "${getExe config.programs.hyprlock.package}";
  hyprctl = "${getExe' (if config.wayland.windowManager.hyprland.package != null then config.wayland.windowManager.hyprland.package else osConfig.programs.hyprland.package) "hyprctl"}";
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
        "${getExe portalPackage}, screencopy, allow"
      ];

      ecosystem = {
        no_update_news = true;
        no_donation_nag = true;
      };
    };
  };
}
