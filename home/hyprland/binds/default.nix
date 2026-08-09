{ config, lib, osConfig, inputs, pkgs, ... }: with lib; with builtins; {
  imports = inputs.noxa.lib.nixDirectoryToList ./.;

  wayland.windowManager.hyprland = {
    settings.bind = [
      {
        _args = [
          (generators.mkLuaInline "mainMod .. \" + Backspace\"")
          (generators.mkLuaInline "hl.dsp.submap(\"clean\")")
        ];
      }
    ];

    submaps.clean.settings.bind = [
      {
        _args = [
          (generators.mkLuaInline "mainMod .. \" + Backspace\"")
          (generators.mkLuaInline "hl.dsp.submap(\"reset\")")
        ];
      }
    ];
  };
}
