{ config, lib, ... }: with lib;
{
  config = {
    services.timesyncd = {
      enable = false;
    };
    services.chrony = {
      enable = true;
    };
  };
}
