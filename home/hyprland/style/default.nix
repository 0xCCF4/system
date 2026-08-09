{ config, lib, osConfig, inputs, pkgs, ... }: with lib; with builtins; {
  imports = inputs.noxa.lib.nixDirectoryToList ./.;

  wayland.windowManager.hyprland.settings = {
    config = {
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
    };

    curve = {
      _args = [
        "easeInOutQuart"
        {
          type = "bezier";
          points = [
            [ 0.86 0 ]
            [ 0.07 1 ]
          ];
        }
      ];
    };

    animation = [
      { leaf = "windows"; enabled = true; speed = 7; bezier = "easeInOutQuart"; }
      { leaf = "windowsIn"; enabled = true; speed = 7; bezier = "default"; style = "popin 80%"; }
      { leaf = "windowsOut"; enabled = true; speed = 7; bezier = "default"; style = "popin 80%"; }
      { leaf = "windowsMove"; enabled = true; speed = 5; bezier = "default"; }
      { leaf = "border"; enabled = true; speed = 10; bezier = "default"; }
      { leaf = "borderangle"; enabled = true; speed = 8; bezier = "default"; }
      { leaf = "fade"; enabled = true; speed = 2; bezier = "default"; }
      { leaf = "workspaces"; enabled = true; speed = 6; bezier = "default"; }
    ];
  };
}
