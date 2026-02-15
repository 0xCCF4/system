{ config, lib, osConfig, noxa, pkgs, ... }: with lib; with builtins; {
  wayland.windowManager.hyprland.settings =
    let
      gromit = config.services.gromit-mpx.package;
      gromit-execstart = "${toString config.systemd.user.services.gromit-mpx.Service.ExecStart}";
    in
    mkIf config.services.gromit-mpx.enable {
      workspace = [ "special:gromit, gapsin:0, gapsout:0, on-created-empty: ${gromit-execstart}" ];
      windowrulev2 = [
        "workspace special:gromit silent, class:^(Gromit-mpx)$"
        "noblur, class:^(Gromit-mpx)$"
        "opacity 1 override, class:^(Gromit-mpx)$"
        "noshadow, class:^(Gromit-mpx)$"
        "suppressevent fullscreen, class:^(Gromit-mpx)$"
        "size 100% 100%, class:^(Gromit-mpx)$"
      ];
      bind = [
        "$mainMod, t, togglespecialworkspace, gromit"
        "$mainMod, t, exec, ${gromit}/bin/gromit-mpx -t"
      ];
    };
}
