{ config
, pkgs
, lib
, osConfig
, mine
, ...
}:
with lib;
{
  config = {
    services.mako = {
      enable = mkDefault ((mine.lib.evalMissingOption osConfig "mine.presets.isWorkstation" false) && osConfig.programs.hyprland.enable);
      settings = {
        #backgroundColor = "#${colors.base01}";
        #borderColor = "#${colors.base0E}";
        #borderRadius = 5;
        #borderSize = 2;
        #textColor = "#${colors.base04}";
        layer = "overlay";
      };
    };
  };
}
