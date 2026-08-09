{ config, lib, osConfig, inputs, pkgs, ... }: with lib; with builtins; {
  imports = inputs.noxa.lib.nixDirectoryToList ./.;

  wayland.windowManager.hyprland.settings = {
    bind = [
      {
        _args = [
          (generators.mkLuaInline "mainMod .. \" + R\"")
          (generators.mkLuaInline "hl.dsp.submap(\"resize\")")
        ];
      }
    ];

    # Resize the active window by a fraction of its current size, with a
    # floor so small windows can still grow/shrink by a usable amount.
    resizeBy = {
      # resizeBy(dx, dy) is a factory: it must RETURN a closure for hl.bind to
      # call later on keypress, not perform the resize itself
      _var = generators.mkLuaInline ''
        function(dx, dy)
          return function()
            local w = hl.get_active_window()
            if w then
              local function delta(size, frac)
                if frac == 0 then
                  return 0
                end
                local d = size * frac
                if math.abs(d) < 20 then
                  d = 20 * (d < 0 and -1 or 1)
                end
                return d
              end
              hl.dispatch(hl.dsp.window.resize({ x = delta(w.size.x, dx), y = delta(w.size.y, dy), relative = true }))
            end
          end
        end
      '';
    };
  };

  wayland.windowManager.hyprland.submaps.resize.settings = {
    bind =
      let
        resetBind = keys: {
          _args = [
            (generators.mkLuaInline keys)
            (generators.mkLuaInline "hl.dsp.submap(\"reset\")")
          ];
        };
        resizeBind = keys: dx: dy: {
          _args = [
            (generators.mkLuaInline keys)
            (generators.mkLuaInline "resizeBy(${toString dx}, ${toString dy})")
            { repeating = true; }
          ];
        };
      in
      [
        (resetBind "mainMod .. \" + Escape\"")
        (resetBind "\"Escape\"")
        (resetBind "\"Return\"")

        (resizeBind "mainMod .. \" + h\"" (-0.1) 0)
        (resizeBind "mainMod .. \" + l\"" 0.1 0)
        (resizeBind "mainMod .. \" + k\"" 0 (-0.1))
        (resizeBind "mainMod .. \" + j\"" 0 0.1)
        (resizeBind "mainMod .. \" + Left\"" (-0.1) 0)
        (resizeBind "mainMod .. \" + Right\"" 0.1 0)
        (resizeBind "mainMod .. \" + Up\"" 0 (-0.1))
        (resizeBind "mainMod .. \" + Down\"" 0 0.1)

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
