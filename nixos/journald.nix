{ config, lib, ... }:
with lib;
{
  config = mkIf config.mine.presets.isWorkstation {
    services.journald.extraConfig = ''
      SystemMaxUse=1G
      SystemMaxFileSize=50M
    '';
  };
}
