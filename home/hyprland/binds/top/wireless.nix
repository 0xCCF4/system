{ pkgs
, lib
, osConfig
, config
, ...
}:
with lib;
with builtins;
let
  rfkill = getExe' pkgs.util-linux "rfkill";
in
{
  wayland.windowManager.hyprland.settings = {
    bind = [
      {
        _args = [
          "XF86RFKill"
          (generators.mkLuaInline "hl.dsp.exec_cmd(\"${rfkill} toggle all\")")
          { locked = true; }
        ];
      }
    ];
  };
}
