{ config
, pkgs
, lib
, mine
, osConfig
, ...
}:
with lib;
{
  imports = [
    ./unfree.nix
  ];

  options.home.mine.slack = with types; {
    enable = mkOption {
      type = bool;
      default = false;
      description = "Enable slack desktop app";
    };
    package = mkOption {
      type = types.package;
      default = pkgs.slack;
      description = "The slack package to use";
    };
  };

  config =
    let
      cfg = config.home.mine.slack;
    in
    mkIf cfg.enable {
      home.packages = [
        cfg.package
      ];
      wayland.windowManager.hyprland.settings.permission = [
        "${cfg.package}/bin/slack, screencopy, allow"
      ];
      home.mine.unfree.allowList = [
        "slack"
      ];
    };
}
