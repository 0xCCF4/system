{ pkgs, lib, osConfig, config, ... }: with lib; with builtins; let

in
{
  wayland.windowManager.hyprland.settings = {
    bindl = [
      ", XF86AudioMute, exec, ${getExe' pkgs.wireplumber "wpctl"} set-mute @DEFAULT_AUDIO_SINK@ toggle"
    ];

    bindel = [
      ", XF86AudioRaiseVolume, exec, ${getExe' pkgs.wireplumber "wpctl"} set-volume @DEFAULT_AUDIO_SINK@ 5%+"
      ", XF86AudioLowerVolume, exec, ${getExe' pkgs.wireplumber "wpctl"} set-volume @DEFAULT_AUDIO_SINK@ 5%-"
    ];
  };
}
