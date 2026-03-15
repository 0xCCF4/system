{ lib, self, config, mailserver, specialArgs, ... }: with lib; {
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

    containers.mailserver =
      let
        mailserverConfig = config.containers.mailserver.config;
        hostConfig = config;
      in
      {
        autoStart = true;
        privateNetwork = true;
        hostAddress = "192.168.100.10";
        localAddress = "192.168.100.11";
        hostAddress6 = "fc00::1";
        localAddress6 = "fc00::2";
        forwardPorts = [
          { hostPort = 25; containerPort = 25; }
          { hostPort = 993; containerPort = 993; } # IMAPS
          { hostPort = 465; containerPort = 465; } # SMTPS
          { hostPort = 80; containerPort = 80; } # ACME HTTP challenge
        ];
        ephemeral = true;
        bindMounts.certs = {
          hostPath = "/persist/data/mailserver/certs";
          mountPoint = mailserverConfig.security.acme.certs.${mailserverConfig.mailserver.fqdn}.directory;
          isReadOnly = false;
        };
        bindMounts.acme = {
          hostPath = "/persist/cache/acme";
          mountPoint = "/var/lib/acme";
          isReadOnly = false;
        };
        inherit specialArgs;
        config = { config, pkgs, lib, ... }: {
          imports = [
            mailserver.nixosModules.mailserver
            self.nixosModules.dns
          ];
          system.stateVersion = hostConfig.system.stateVersion;
          networking.firewall.enable = true;
          # Use systemd-resolved inside the container
          # Workaround for bug https://github.com/NixOS/nixpkgs/issues/162686
          networking.useHostResolvConf = lib.mkForce false;

          security.acme = {
            acceptTerms = true;
            defaults.email = "security@johmat.de";
            certs.${config.mailserver.fqdn} = {
              # Further setup required, check the manual:
              # https://nixos.org/manual/nixos/stable/#module-security-acme
              listenHTTP = ":80";
            };
          };

          environment.systemPackages = with pkgs; [
            kitty
          ];

          mailserver = {
            enable = true;
            stateVersion = 3;
            fqdn = "mail.johmat.de";
            domains = [ "johmat.de" ];

            # reference an existing ACME configuration
            x509.useACMEHost = config.mailserver.fqdn;

            localDnsResolver = false;

            # A list of all login accounts. To create the password hashes, use
            # nix-shell -p mkpasswd --run 'mkpasswd -s'
            loginAccounts = {
              "postmaster@johmat.de" = {
                hashedPassword = "$y$j9T$qgo2xCuskPwkggKYEvTbY.$C/.YHb2UhhYJLF6YIfnZabGjFi3nKAFDwbHV8ts2Bm0";
                aliases = [ "@johmat.de" ];
              };
            };
          };
        };
      };
    networking.nat = {
      enable = true;
      # Use "ve-*" when using nftables instead of iptables
      internalInterfaces = [ "ve-+" ];
      externalInterface = "lan";
      # Lazy IPv6 connectivity for the container
      enableIPv6 = true;
    };
  };
}
