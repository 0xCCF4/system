{ pkgs
, lib
, config
, ...
}:
with lib;
{
  options.mine.steam = with types; mkOption {
    type = bool;
    default = false;
    description = "Add steam to the system.";
  };

  config =
    mkIf config.mine.steam {
      programs.steam.enable = mkDefault true;
      programs.steam.gamescopeSession.enable = mkDefault true;

      mine.unfree.allowList = [
        "steam"
        "steam-original"
        "steam-run"
        "steam-unwrapped"
      ];
    };
}
