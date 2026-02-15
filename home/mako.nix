{ config
, pkgs
, lib
, osConfig
, self
, ...
}:
with lib;
{
  config = {
    services.mako = {
      enable = mkDefault ((self.lib.evalMissingOption osConfig "mine.presets.isWorkstation" false) && (osConfig.programs.hyprland.enable || config.wayland.windowManager.hyprland.enable));
      settings = {
        #backgroundColor = "#${colors.base01}";
        #borderColor = "#${colors.base0E}";
        #borderRadius = 5;
        #borderSize = 2;
        #textColor = "#${colors.base04}";
        layer = "overlay";
        width = 500;
      };
    };
  };
}
