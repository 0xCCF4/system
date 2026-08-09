{ pkgs, lib, osConfig, config, ... }: with lib; with builtins; let
  mkBind = mods: key: dispatcherExpr: {
    _args = [
      (generators.mkLuaInline "mainMod .. \" + ${mods}${key}\"")
      (generators.mkLuaInline dispatcherExpr)
    ];
  };
  mkModBind = key: dispatcherExpr: mkBind "" key dispatcherExpr;
  mkShiftBind = key: dispatcherExpr: mkBind "SHIFT + " key dispatcherExpr;

  directions = {
    l = "right";
    h = "left";
    k = "up";
    j = "down";
    Left = "left";
    Right = "right";
    Up = "up";
    Down = "down";
  };

  # workspace 10 is bound to the "0" key
  workspaceKeys = map (n: if n == 10 then "0" else toString n) (range 1 10);
in
{
  wayland.windowManager.hyprland.settings = {
    bind =
      (mapAttrsToList (key: direction: mkModBind key "hl.dsp.focus({ direction = \"${direction}\" })") directions)
      ++ (mapAttrsToList (key: direction: mkShiftBind key "hl.dsp.window.move({ direction = \"${direction}\" })") directions)
      ++ (imap0 (i: key: mkModBind key "hl.dsp.focus({ workspace = ${toString (i + 1)} })") workspaceKeys)
      ++ (imap0 (i: key: mkShiftBind key "hl.dsp.window.move({ workspace = ${toString (i + 1)} })") workspaceKeys)
      ++ [
        # Pin Window
        (mkModBind "p" "hl.dsp.window.pin()")

        # Move to scratchpad
        (mkModBind "c" "hl.dsp.workspace.toggle_special()")
        (mkShiftBind "c" "hl.dsp.window.move({ workspace = \"special\" })")
        {
          _args = [
            (generators.mkLuaInline "mainMod .. \" + ALT + c\"")
            (generators.mkLuaInline "hl.dsp.window.move({ workspace = \"previous\" })")
          ];
        }
      ];

    # NOTE: gesture semantics changed with the new dispatcher-based config;
    # verify these on real touchpad hardware.
    gesture = [
      { fingers = 3; direction = "horizontal"; action = "workspace"; }
      { fingers = 3; direction = "horizontal"; mods = "SHIFT"; action = "move"; }
      { fingers = 3; direction = "down"; action = "special"; }
    ];
  };
}
