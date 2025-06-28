{ config
, lib
, mine
, osConfig
, ...
}:
with lib; with builtins;
{
  options.home.mine.unfree = with types;
    {
      enable = mkOption {
        type = bool;
        default = mine.lib.evalMissingOption osConfig "mine.presets.isWorkstation" false;
        description = "Enable unfree package management";
      };
      allowAll = mkOption {
        type = bool;
        default = false;
        description = "Allow all unfree packages";
      };
      allowList = mkOption {
        type = listOf str;
        default = [ ];
        description = "List of allowed unfree packages";
      };
    };

  config =
    let
      cfg = config.home.mine.unfree;
    in
    mkIf cfg.enable {
      nixpkgs.config = mkIf (!osConfig.home-manager.useGlobalPkgs) {
        allowUnfree = cfg.allowAll;
        allowUnfreePredicate = pkg: builtins.elem (getName pkg) cfg.allowList;
      };
    };
}
