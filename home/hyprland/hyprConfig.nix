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
    configType = mkDefault "lua";
    settings = {
      # Lua locals shared across every other hyprland settings file in this
      # config (they're all merged into one generated hyprland.lua).
      terminal = { _var = "${terminal}"; };
      fileManager = { _var = fileManager; };
      menu = { _var = "${rofi} -show drun"; };
      reloadWaybar = { _var = "pkill waybar; ${waybar} &"; };
      lock = { _var = "${lock}"; };
      hyprctl = { _var = "${hyprctl}"; };
      mainMod = { _var = "SUPER"; };

      config = {
        input = {
          kb_layout = mkDefault osConfig.mine.locale.keyboardLayout;
          kb_variant = mkDefault osConfig.mine.locale.keyboardVariant;
          numlock_by_default = true;

          touchpad = {
            natural_scroll = mkDefault true;
          };
        };

        dwindle = {
          preserve_split = true;
        };

        master = {
          new_status = "master";
        };

        ecosystem = {
          no_update_news = true;
          no_donation_nag = true;
        };
      };

      env = [
        { _args = [ "GTK_THEME" "Tokyo-Night-Dark" ]; }
        { _args = [ "GTK_ICON_THEME" "Adwaita" ]; }
        { _args = [ "XCURSOR_THEME" "Adwaita" ]; }

        { _args = [ "XCURSOR_SIZE" "24" ]; }
        { _args = [ "HYPRCURSOR_SIZE" "24" ]; }
        { _args = [ "XDG_CURRENT_DESKTOP" "Hyprland" ]; }
        { _args = [ "XDG_SESSION_TYPE" "wayland" ]; }

        { _args = [ "_JAVA_AWT_WM_NONREPARENTING" "1" ]; }
      ];

      permission = [
        "${getExe portalPackage}, screencopy, allow"
      ];
    };
  };
}
