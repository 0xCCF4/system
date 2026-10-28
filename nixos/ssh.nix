{ config, lib, noxa, ... }: with lib;
let
  # Hosts mx administrates the other hosts from
  adminHosts = [
    "ignis"
    "solis"
  ];
  hostName = config.networking.hostName;
in
{
  config = {
    services.openssh = {
      enable = mkDefault true;
      settings.PasswordAuthentication = mkDefault false;
      settings.KbdInteractiveAuthentication = mkDefault false;
    };

    programs.mosh.enable = mkDefault config.services.openssh.enable;

    ssh.grants = mkIf (elem hostName adminHosts) (genAttrs
      (filter (name: name != hostName) noxa.managedNodes)
      (to: {
        from = "mx";
        to.node = to;
        to.user = "mx";
        options.pty = true;
        options.agentForwarding = true;
        options.allowPortForwarding = true;
        to.hostname = mkDefault "${to}.vlan";
      }));
  };
}
