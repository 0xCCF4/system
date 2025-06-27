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
    #persistence.cache.files = [
    #    ".z"
    #];

    #persistence.cache.directories = [
    #    ".cache/nushell_history"
    #];

    programs.nushell = {
      enable = mkDefault true;
    };
  };
}
