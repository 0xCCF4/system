{ config
, pkgs
, lib
, self
, osConfig
, ...
}:
with lib;
{
  imports = [
    ./persistence.nix
  ];

  options.home.mine.timetrax = with types;
    {
      enable = mkOption {
        type = bool;
        default = self.lib.evalMissingOption osConfig.mine.presets "isWorkstation" false;
        description = "Enable TimeTrax";
      };

      package = mkOption {
        type = pkgs.lib.types.package;
        default = pkgs.timetrax;
        description = "The TimeTrax package to use.";
      };
    };

  config =
    let
      cfg = config.home.mine.timetrax;
    in
    lib.mkIf cfg.enable {
      home.mine.persistence.cache.directories = [
        ".timetrax "
      ];

      home.packages = [ cfg.package ];
    };
}

