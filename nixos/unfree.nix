{ config
, pkgs
, lib
, ...
}:
with lib; with builtins;
{
  imports = [
    ./presets.nix
  ];

  options.mine.unfree =
    with types;
    {
      allowWhitelisted = mkOption {
        type = bool;
        default = config.mine.presets.isWorkstation;
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
      allowUserWhitelist = mkOption {
        type = bool;
        default = true;
        description = "Allow users to specify additional unfree packages in their home-manager configuration";
      };
    };

  config =
    let
      cfg = config.mine.unfree;
    in
    {
      nixpkgs.config = mkIf cfg.allowWhitelisted {
        allowUnfree = cfg.allowAll;
        allowUnfreePredicate = pkg: elem (getName pkg) cfg.allowList;
      };
      mine.unfree.allowList = mkIf (cfg.allowUserWhitelist) (mkMerge (map (user: config.home-manager.users.${user}.home.mine.unfree.allowList) (config.mine.users or [ ])));
    };
}
