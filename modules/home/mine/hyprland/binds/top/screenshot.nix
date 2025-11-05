{ pkgs, lib, osConfig, config, ... }: with lib; with builtins; let

in
{
  wayland.windowManager.hyprland.settings =
    let
      grim = "${pkgs.grim}/bin/grim";
      slurp = "${pkgs.slurp}/bin/slurp";
      wlcopy = "${pkgs.wl-clipboard}/bin/wl-copy";
    in
    {
      bind = [
        "$mainMod SHIFT CONTROL, p, exec, ${grim} - | ${wlcopy}"
        "$mainMod SHIFT, p, exec, ${grim} -g \"$(${slurp})\" - | ${wlcopy}"
      ];
    };
}
