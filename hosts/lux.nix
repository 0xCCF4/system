{ lib, self, config, ... }: with lib; {
  imports = [
    ../hardware/netcup.nix
  ] ++ self.lib.optionalsIfExist [
    ../external/private/hosts/lux.nix
  ];

  config = {
    # General settings
    networking.hostName = "lux";
    mine.presets.primary = "server";
    networking.hostId = "9a5839bd";

    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
    boot.kernelModules = [ "veth" "kvm" ];

    mine.admins = [ "mx" ];

    # SSH
    services.openssh = {
      enable = true;
      ports = [ 5555 22 ];
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
        GatewayPorts = "yes";
      };
    };

    mine.persistence.enable = true;

    # todo remove
    security.sudo.wheelNeedsPassword = false;

    # Remote unlock luks via ssh+tor
    mine.boot.remoteUnlock = true;
    boot.initrd.network.ssh.port = 4444;
    mine.boot.tor.enable = true;
    mine.boot.tor.ports = [
      {
        port = 22;
        bindPort = config.boot.initrd.network.ssh.port;
      }
    ];
  };
}
