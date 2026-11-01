{ config, lib, ... }: with lib;
{
  config = {
    services.timesyncd = {
      enable = false;
    };
    # NTS (RFC 8915): authenticated time, a network on the path (hotspot, LAN) can't shift
    # the clock.
    services.chrony = {
      enable = true;
      enableNTS = true;
      servers = [ "ptbtime1.ptb.de" "ptbtime2.ptb.de" "ptbtime3.ptb.de" "ptbtime4.ptb.de" ];
      # NTS needs TLS, TLS a roughly correct clock: the first clock update doesn't check the
      # certificates' validity period (empty RTC battery, clock far off)
      extraConfig = ''
        nocerttimecheck 1
      '';
    };
  };
}
