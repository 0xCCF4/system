{ config
, pkgs
, lib
, osConfig
, self
, ...
}:
with lib;
with builtins;
{
  config =
    let
      shell = config.programs.fish;
    in
    {
      programs.alacritty = {
        enable = mkDefault false;
        settings = {
          terminal.shell = mkIf shell.enable (mkDefault "${getExe shell.package}");
        };
      };
    };
}
