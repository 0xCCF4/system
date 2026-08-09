{ pkgs, lib, osConfig, config, ... }: with lib; with builtins; let
  brightnessctl = getExe pkgs.brightnessctl;
in
{
  wayland.windowManager.hyprland.settings = {
    bind = [
      {
        _args = [
          "XF86MonBrightnessUp"
          (generators.mkLuaInline "hl.dsp.exec_cmd(\"${brightnessctl} set 10%+\")")
          { repeating = true; }
        ];
      }
      {
        _args = [
          "XF86MonBrightnessDown"
          (generators.mkLuaInline "hl.dsp.exec_cmd(\"${brightnessctl} set 10%-\")")
          { repeating = true; }
        ];
      }
    ];
  };
}
