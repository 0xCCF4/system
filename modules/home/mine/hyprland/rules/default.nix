{ config, lib, osConfig, noxa, pkgs, ... }: with lib; with builtins; {
  imports = noxa.lib.nixDirectoryToList ./.;

  wayland.windowManager.hyprland.settings = {
    windowrulev2 = [
      "suppressevent maximize, class:.*"
    ];
  };
}
