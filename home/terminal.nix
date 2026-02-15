{ config
, pkgs
, lib
, osConfig
, self
, ...
}:
with lib; with builtins;
{
  config =
    let
      shell = config.programs.fish;
      isWorkstation = self.lib.evalMissingOption osConfig "mine.presets.isWorkstation" false;
    in
    {
      programs.alacritty = {
        enable = mkDefault false;
        settings = {
          terminal.shell = mkIf shell.enable (mkDefault "${getExe shell.package}");
        };
      };

      programs.kitty = {
        enable = mkDefault isWorkstation;
        enableGitIntegration = mkDefault true;
        settings = {
          shell = mkIf shell.enable (mkDefault "${getExe shell.package}");
          disable_ligatures = "cursor";
        };
      };
    };
}
