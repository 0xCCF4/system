{ config, lib, osConfig, inputs, pkgs, ... }: with lib; with builtins; {
  imports = inputs.noxa.lib.nixDirectoryToList ./.;

  wayland.windowManager.hyprland.settings = {
    bind = [
      "$mainMod, R, submap, resize"
    ];
  };

  wayland.windowManager.hyprland.submaps.resize.settings = {
    bind = [
      "$mainMod, Escape, submap, reset"
      ", Escape, submap, reset"
      ", Enter, submap, reset"
    ];

    binde =
      let
        resizeAmount = "10%";
      in
      [
        "$mainMod, h, resizeactive, ${resizeAmount} 0"
        "$mainMod, l, resizeactive, ${resizeAmount} 0"
        "$mainMod, k, resizeactive, 0 -${resizeAmount}"
        "$mainMod, j, resizeactive, 0 ${resizeAmount}"
        "$mainMod, Left, resizeactive, -${resizeAmount} 0"
        "$mainMod, Right, resizeactive, ${resizeAmount} 0"
        "$mainMod, Up, resizeactive, 0 -${resizeAmount}"
        "$mainMod, Down, resizeactive, 0 ${resizeAmount}"
      ];

    bindm = [
      "$mainMod, mouse:272, movewindow"
      "$mainMod, mouse:273, resizeactive"
    ];
  };
}
