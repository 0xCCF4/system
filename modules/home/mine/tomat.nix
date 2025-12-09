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
    services.tomat = {
      enable = mkDefault (mine.lib.evalMissingOption osConfig "mine.presets.isWorkstation" false);
      settings = {
        notifications = {
          enabled = true;
          icon = "auto";
          timeout = 120 * 1000;
        };
        timer = {
          auto_advance = false;
          break = 5;
          work = 25;
        };
      };
    };
  };
}
