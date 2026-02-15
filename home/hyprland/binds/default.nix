{ config, lib, osConfig, inputs, pkgs, ... }: with lib; with builtins; {
  imports = inputs.noxa.lib.nixDirectoryToList ./.;

  wayland.windowManager.hyprland = {
    settings.bind = [
      "$mainMod, Backspace, submap, clean"
    ];

    submaps.clean.settings.bind = [
      "$mainMod, Backspace, submap, reset"
    ];
  };
}
