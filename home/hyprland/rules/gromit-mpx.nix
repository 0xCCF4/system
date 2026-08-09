{ config, lib, osConfig, noxa, pkgs, ... }: with lib; with builtins; {
  wayland.windowManager.hyprland.settings =
    let
      gromit = config.services.gromit-mpx.package;
      gromit-execstart = "${toString config.systemd.user.services.gromit-mpx.Service.ExecStart}";
    in
    mkIf config.services.gromit-mpx.enable {
      workspace_rule = {
        workspace = "special:gromit";
        gaps_in = 0;
        gaps_out = 0;
        on_created_empty = "${gromit-execstart}";
      };

      window_rule = {
        match.class = "^(Gromit-mpx)$";
        workspace = "special:gromit silent";
        no_blur = true;
        opacity = "1 override";
        no_shadow = true;
        suppress_event = "fullscreen";
        size = [ "monitor_w" "monitor_h" ];
      };

      bind = [
        {
          _args = [
            (generators.mkLuaInline "mainMod .. \" + t\"")
            (generators.mkLuaInline "hl.dsp.workspace.toggle_special(\"gromit\")")
          ];
        }
        {
          _args = [
            (generators.mkLuaInline "mainMod .. \" + t\"")
            (generators.mkLuaInline "hl.dsp.exec_cmd(\"${gromit}/bin/gromit-mpx -t\")")
          ];
        }
      ];
    };
}
