{ pkgs, lib, osConfig, config, ... }: with lib; with builtins; let

in
{
  wayland.windowManager.hyprland.settings = {
    bind = [
      # Start apps
      "$mainMod, Return, exec, $terminal"
      "$mainMod, E, exec, $fileManager"
      "$mainMod, D, exec, $menu"
      "$mainMod, S, exec, $snip"

      # Lock, reload, exit
      "$mainMod, P, exec, $hyprctl reload"
      "$mainMod, M, exit,"
      "$mainMod ALT, L, exec, $lock"
      "$mainMod ALT CONTROL, L, exec, $lock"
      "$mainMod ALT CONTROL, L, exec, sleep 1 && systemctl suspend"

      # Close windows
      "$mainMod, Q, killactive,"
      "$mainMod SHIFT, Q, forcekillactive,"

      # Toggle floating
      "$mainMod, V, togglefloating,"

      # Toggle fullscreen
      "$mainMod, F, fullscreen,"

      # Toggle split
      "$mainMod, G, togglesplit,"
    ];
  };
}
