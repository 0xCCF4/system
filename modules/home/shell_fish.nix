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
    home.mine.persistence.cache.directories = [
      ".local/share/fish"
    ];

    programs.fish = {
      enable = mkDefault true;
    };
  };
}
