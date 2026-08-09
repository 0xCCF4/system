{ pkgs, lib, osConfig, config, ... }: with lib; with builtins; {
  wayland.windowManager.hyprland.settings = {
    bind = [
      {
        _args = [
          (generators.mkLuaInline "mainMod .. \" + mouse:272\"")
          (generators.mkLuaInline "hl.dsp.window.drag()")
          { mouse = true; }
        ];
      }
      {
        _args = [
          (generators.mkLuaInline "mainMod .. \" + mouse:273\"")
          (generators.mkLuaInline "hl.dsp.window.resize()")
          { mouse = true; }
        ];
      }
    ];
  };
}
