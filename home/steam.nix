{ config
, pkgs
, lib
, osConfig
, self
, ...
}:
with lib;
{
  imports = [
    ./traits.nix
    ./persistence.nix
  ];

  config = mkIf ((self.lib.evalMissingOption osConfig "mine.steam" false) && config.home.mine.traits.hasGaming) {
    home.packages = with pkgs; [
      protonup-ng
    ];

    home.sessionVariables = {
      STEAM_EXTRA_COMPAT_TOOLS_PATHS = "/home/${config.home.username}/.steam/root/compatibilitytools.d";
    };

    home.mine.persistence.cache.directories = [
      {
        directory = ".local/share/Steam";
        method = "symlink";
      }
      {
        directory = ".steam";
        method = "symlink";
      }
    ];

    home.mine.persistence.data.directories = [
      "GameSaves"
    ];
  };
}
