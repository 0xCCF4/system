{ config, lib, ... }: with lib;
{
  config = {
    security.sudo.wheelNeedsPassword = mkIf config.age.rekey.initialRollout (mkDefault false);
    security.pam.services.su.requireWheel = mkDefault true; # only wheel members may use su (root has no password anyway, admins use sudo)
  };
}
