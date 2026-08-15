{ config
, lib
, pkgs
, ...
}:
with lib;
{
  imports = [
    ./persistence.nix
  ];
  config = {
    home.mine.persistence.cache.directories = [
      ".local/share/containers"
    ];
  };
}
