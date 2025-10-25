{ config, lib, osConfig, noxa, pkgs, ... }: with lib; with builtins; {
  imports = noxa.lib.nixDirectoryToList ./.;

  wayland.windowManager.hyprland = {
    settings.bind = [
      "$mainMod, Backspace, submap, clean"
    ];

    submaps.clean.settings.bind = [
      "$mainMod, Backspace, submap, reset"
    ];
  };
}
