{ config, lib, osConfig, inputs, pkgs, ... }: with lib; with builtins; {
  imports = inputs.noxa.lib.nixDirectoryToList ./.;

  wayland.windowManager.hyprland.settings = {
    #animations.enabled = false;
    decoration.blur.enabled = false;
    decoration.shadow.enabled = false;

    cursor = {
      inactive_timeout = 10;
    };

    general = {
      border_size = 2;
      gaps_in = 2;
      gaps_out = 1;
    };

    animations = {
      bezier = [ "easeInOutQuart, 0.86, 0, 0.07, 1" ];
      animation = [
        "windows, 1, 7, easeInOutQuart"
        "windowsIn, 1, 7, default, popin 80%"
        "windowsOut, 1, 7, default, popin 80%"
        "windowsMove, 1, 5, default"
        "border, 1, 10, default"
        "borderangle, 1, 8, default"
        "fade, 1, 2, default"
        "workspaces, 1, 6, default"
      ];
    };
  };
}
