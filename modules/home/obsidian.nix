{ config
, pkgs
, lib
, ...
}:
with lib;
{
  imports = [
    ./persistence.nix
    ./traits.nix
  ];

  options.home.mine = with types;
    {
      obsidian.enable = mkOption {
        type = bool;
        default = config.home.mine.traits.hasOffice;
        description = "Enable Obsidian";
      };
      obsidian.autostart = mkOption {
        type = bool;
        default = true;
        description = "Enable autostart for Obsidian";
      };
    };

  config = lib.mkIf config.home.mine.obsidian.enable {
    home.mine.persistence.cache.directories = [
      ".config/obsidian"
    ];

    home.packages = [ pkgs.obsidian ];

    home.mine.unfree.allowList = [ "obsidian" ];

    home.mine.autostart = mkIf config.home.mine.obsidian.autostart [ pkgs.obsidian ];
  };
}
