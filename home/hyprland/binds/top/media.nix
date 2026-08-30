{ pkgs
, lib
, osConfig
, config
, ...
}:
with lib;
with builtins;
let
  playerctl = getExe pkgs.playerctl;
in
{
  wayland.windowManager.hyprland.settings = {
    bind = [
      {
        _args = [
          "XF86AudioPlay"
          (generators.mkLuaInline "hl.dsp.exec_cmd(\"${playerctl} play-pause\")")
          { locked = true; }
        ];
      }
      {
        _args = [
          "XF86AudioNext"
          (generators.mkLuaInline "hl.dsp.exec_cmd(\"${playerctl} next\")")
          { locked = true; }
        ];
      }
      {
        _args = [
          "XF86AudioPrev"
          (generators.mkLuaInline "hl.dsp.exec_cmd(\"${playerctl} previous\")")
          { locked = true; }
        ];
      }
      {
        _args = [
          "XF86AudioStop"
          (generators.mkLuaInline "hl.dsp.exec_cmd(\"${playerctl} stop\")")
          { locked = true; }
        ];
      }
    ];
  };
}
