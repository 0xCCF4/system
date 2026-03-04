{ lib, self, config, ... }: with lib; {
  imports = [
    ../hardware/netcup.nix
    # self.inputs.mailserver.nixosModules.mailserver
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

    # security.acme = {
    #   acceptTerms = true;
    #   defaults.email = "security@johmat.de";
    #   certs.${config.mailserver.fqdn} = {
    #     # Further setup required, check the manual:
    #     # https://nixos.org/manual/nixos/stable/#module-security-acme
    #     listenHTTP = ":80";
    #   };
    # };

    # mailserver = {
    #   enable = true;
    #   stateVersion = 3;
    #   fqdn = "mail.johmat.de";
    #   domains = [ "johmat.de" ];

    #   # reference an existing ACME configuration
    #   x509.useACMEHost = config.mailserver.fqdn;

    #   localDnsResolver = false;

    #   # A list of all login accounts. To create the password hashes, use
    #   # nix-shell -p mkpasswd --run 'mkpasswd -s'
    #   loginAccounts = {
    #     "postmaster@johmat.de" = {
    #       hashedPassword = "$y$j9T$qgo2xCuskPwkggKYEvTbY.$C/.YHb2UhhYJLF6YIfnZabGjFi3nKAFDwbHV8ts2Bm0";
    #       aliases = [ "@johmat.de" ];
    #     };
    #   };
    # };
  };
}
