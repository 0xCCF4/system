{ config
, pkgs
, lib
, osConfig
, mine
, ...
}:
with lib; with builtins;
{
  config =
    let
      shell = config.programs.fish;
      isWorkstation = mine.lib.evalMissingOption osConfig "mine.presets.isWorkstation" false;
    in
    {
      programs.alacritty = {
        enable = mkDefault false;
        settings = {
          terminal.shell = mkIf shell.enable (mkDefault "${shell.package}/bin/${shell.package.pname}");
        };
      };

      programs.kitty = {
        enable = mkDefault isWorkstation;
        enableGitIntegration = mkDefault true;
        settings = {
          shell = mkIf shell.enable (mkDefault "${shell.package}/bin/${shell.package.pname}");
          disable_ligatures = "cursor";
        };
      };
    };
}
