{ config, lib, ... }: with lib; {
  config = {
    services.openssh = {
      enable = mkDefault true;
      settings.PasswordAuthentication = mkDefault false;
      settings.KbdInteractiveAuthentication = mkDefault false;
    };
  };
}
