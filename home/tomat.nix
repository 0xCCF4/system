{ config
, pkgs
, lib
, osConfig
, mineSelf
, ...
}:
with lib;
{
  config = {
    services.tomat = {
      # enable = mkDefault (mineSelf.lib.evalMissingOption osConfig "mine.presets.isWorkstation" false);
      settings = {
        notifications = {
          enabled = true;
          icon = "auto";
          timeout = 120 * 1000; # 2 min (ms)
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
