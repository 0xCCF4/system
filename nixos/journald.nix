{ config, lib, ... }:
with lib;
{
  config = mkIf config.mine.presets.isWorkstation {
    services.journald.settings.Journal = {
      SystemMaxUse = "1G";
      SystemMaxFileSize = "100M";
    };
  };
}
