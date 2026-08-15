{ config, lib, ... }: with lib;
{
  config = {
    security.sudo.wheelNeedsPassword = mkIf config.age.rekey.initialRollout (mkDefault false);
  };
}
