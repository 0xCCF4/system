{ inputs
, config
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
    let
      presets = config.mine.presets;
    in
    with types;
    {
      allowWhitelisted = mkOption {
        type = bool;
        default = presets.isWorkstation;
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
      cfg = config.mine.unfree;
    in
    mkIf cfg.allowWhitelisted {
      nixpkgs.config = {
        allowUnfree = cfg.allowAll;
        allowUnfreePredicate = pkg: elem (getName pkg) cfg.allowList;
      };
    };
}
