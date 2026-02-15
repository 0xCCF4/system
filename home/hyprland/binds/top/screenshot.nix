{ pkgs, lib, osConfig, config, ... }: with lib; with builtins; let

in
{
  wayland.windowManager.hyprland.settings =
    let
      grim = getExe pkgs.grim;
      slurp = getExe pkgs.slurp;
      wlcopy = getExe' pkgs.wl-clipboard "wl-copy";
    in
    {
      bind = [
        "$mainMod SHIFT CONTROL, p, exec, ${grim} - | ${wlcopy}"
        "$mainMod SHIFT, p, exec, ${grim} -g \"$(${slurp})\" - | ${wlcopy}"
      ];
    };
}
