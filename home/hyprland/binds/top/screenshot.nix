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
        {
          _args = [
            (generators.mkLuaInline "mainMod .. \" + SHIFT + CONTROL + p\"")
            (generators.mkLuaInline "hl.dsp.exec_cmd(\"${grim} - | ${wlcopy}\")")
          ];
        }
        {
          _args = [
            (generators.mkLuaInline "mainMod .. \" + SHIFT + p\"")
            (generators.mkLuaInline "hl.dsp.exec_cmd('${grim} -g \"$(${slurp})\" - | ${wlcopy}')")
          ];
        }
      ];
    };
}
