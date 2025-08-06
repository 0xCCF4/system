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
        enable = mkDefault false;
        settings = {
          terminal.shell = mkIf shell.enable (mkDefault "${shell.package}/bin/${shell.package.pname}");
        };
      };

      programs.kitty = {
        enable = mkDefault true;
        enableGitIntegration = mkDefault true;
        settings = {
          shell = mkIf shell.enable (mkDefault "${shell.package}/bin/${shell.package.pname}");
        };
      };
    };
}
