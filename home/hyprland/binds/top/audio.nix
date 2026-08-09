{ pkgs, lib, osConfig, config, ... }: with lib; with builtins; let
  wpctl = getExe' pkgs.wireplumber "wpctl";
in
{
  wayland.windowManager.hyprland.settings = {
    bind = [
      {
        _args = [
          "XF86AudioMute"
          (generators.mkLuaInline "hl.dsp.exec_cmd(\"${wpctl} set-mute @DEFAULT_AUDIO_SINK@ toggle\")")
          { locked = true; }
        ];
      }
      {
        _args = [
          "XF86AudioRaiseVolume"
          (generators.mkLuaInline "hl.dsp.exec_cmd(\"${wpctl} set-volume @DEFAULT_AUDIO_SINK@ 5%+\")")
          { locked = true; repeating = true; }
        ];
      }
      {
        _args = [
          "XF86AudioLowerVolume"
          (generators.mkLuaInline "hl.dsp.exec_cmd(\"${wpctl} set-volume @DEFAULT_AUDIO_SINK@ 5%-\")")
          { locked = true; repeating = true; }
        ];
      }
    ];
  };
}
