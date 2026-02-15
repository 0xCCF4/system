{ pkgs, lib, osConfig, config, ... }: with lib; with builtins; let

in
{
  wayland.windowManager.hyprland.settings = {
    binde = [
      ", XF86MonBrightnessUp, exec, ${getExe pkgs.brightnessctl} set 10%+"
      ", XF86MonBrightnessDown, exec, ${getExe pkgs.brightnessctl} set 10%-"
    ];
  };
}
