{ config
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
      isWorkstation = self.lib.evalMissingOption osConfig "mine.presets.isWorkstation" false;
    in
    {
      programs.kitty = {
        enable = mkDefault isWorkstation;
        enableGitIntegration = mkDefault true;
        settings = {
          shell = mkIf shell.enable (mkDefault "${getExe shell.package}");
          disable_ligatures = "cursor";

          # Tab bar on top, always visible, with the active SSH host right-aligned (see tab_bar.py)
          tab_bar_edge = "top";
          tab_bar_min_tabs = 1;
          tab_bar_style = "custom";
        };
      };

      xdg.configFile."kitty/tab_bar.py" = mkIf config.programs.kitty.enable {
        source = ./tab_bar.py;
      };
    };
}
