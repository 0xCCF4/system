{ config, lib, osConfig, noxa, pkgs, ... }: with lib; with builtins; {
  imports = noxa.lib.nixDirectoryToList ./.;

  wayland.windowManager.hyprland.settings = {
    animations.enabled = false;
    decoration.blur.enabled = false;
    decoration.shadow.enabled = false;

    cursor = {
      inactive_timeout = 30;
    };

    general = {
      border_size = 2;
      gaps_in = 2;
      gaps_out = 1;
    };

    #animations = { #todo change
    #  # enabled = true;
    #  bezier = [ "myBezier, 0.05, 0.9, 0.1, 1.05" ];
    #  animation = [
    #    "windows, 1, 7, myBezier"
    #    "windowsOut, 1, 7, default, popin 80%"
    #    "border, 1, 10, default"
    #    "borderangle, 1, 8, default"
    #    "fade, 1, 7, default"
    #    "workspaces, 1, 6, default"
    #  ];
    #};
  };
}
