{ config
, lib
, ...
}:
with lib;
with builtins;
{
  imports = [
    ./persistence.nix
  ];

  config = {
    home.mine.persistence.cache.directories = mkIf (config.programs.zoxide.enable) [
      ".local/share/zoxide"
    ];

    programs.zoxide = {
      enable = mkDefault true;
      options = [
        "--cmd"
        "cd"
      ];
    };
  };
}
