{ config
, pkgs
, lib
, ...
}:
with lib; with builtins;
{
  config =
    let
      shell = config.programs.fish;
    in
    {
      programs.alacritty = {
        enable = mkDefault true;
        settings = {
          terminal.shell = mkIf shell.enable "${shell.package}/bin/${shell.package.pname}";
        };
      };
    };
}
