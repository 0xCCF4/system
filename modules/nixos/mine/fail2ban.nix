{ config
, pkgs
, lib
, ...
}:
with lib;
{
  config = {
    services.fail2ban = {
      ignoreIP = [
        "10.0.0.0/8"
        "192.0.0.0/8"
      ];
    };
  };
}
