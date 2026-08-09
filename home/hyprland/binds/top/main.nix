{ pkgs, lib, osConfig, config, ... }: with lib; with builtins; let
  mkBind = key: dispatcherExpr: { _args = [ (generators.mkLuaInline "mainMod .. \" + ${key}\"") (generators.mkLuaInline dispatcherExpr) ]; };
in
{
  wayland.windowManager.hyprland.settings = {
    bind = [
      # Start apps
      (mkBind "Return" "hl.dsp.exec_cmd(terminal)")
      (mkBind "E" "hl.dsp.exec_cmd(fileManager)")
      (mkBind "D" "hl.dsp.exec_cmd(menu)")

      # Lock, reload, exit
      (mkBind "P" "hl.dsp.exec_cmd(hyprctl .. \" reload\")")
      (mkBind "M" "hl.dsp.exit()")
      {
        _args = [
          (generators.mkLuaInline "mainMod .. \" + ALT + L\"")
          (generators.mkLuaInline "hl.dsp.exec_cmd(lock)")
        ];
      }
      {
        _args = [
          (generators.mkLuaInline "mainMod .. \" + ALT + CONTROL + L\"")
          (generators.mkLuaInline "hl.dsp.exec_cmd(lock)")
        ];
      }
      {
        _args = [
          (generators.mkLuaInline "mainMod .. \" + ALT + CONTROL + L\"")
          (generators.mkLuaInline "hl.dsp.exec_cmd(\"sleep 1 && systemctl suspend\")")
        ];
      }

      # Close windows
      (mkBind "Q" "hl.dsp.window.close()")
      {
        _args = [
          (generators.mkLuaInline "mainMod .. \" + SHIFT + Q\"")
          (generators.mkLuaInline "hl.dsp.window.kill()")
        ];
      }

      # Toggle floating
      (mkBind "V" "hl.dsp.window.float({ action = \"toggle\" })")

      # Toggle fullscreen
      (mkBind "F" "hl.dsp.window.fullscreen({ mode = \"fullscreen\", action = \"toggle\" })")

      # Toggle split
      (mkBind "G" "hl.dsp.layout(\"togglesplit\")")
    ];
  };
}
