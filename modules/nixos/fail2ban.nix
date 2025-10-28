{ config
, pkgs
, lib
, ...
}:
with lib;
{
  config = {
    services.fail2ban = {
      enable = mkDefault config.services.sshd.enable;
    };
  };
}
