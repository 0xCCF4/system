{ inputs
, config
, pkgs
, lib
, ...
}:
with lib; with builtins;
{
  imports = [
    ./persistence.nix
  ];

  config = {
    home.mine.persistence.cache.directories = mkIf (config.programs.fish.enable) [
      ".local/share/fish"
    ];

    programs.fish = {
      enable = mkDefault true;
    };
  };
}
