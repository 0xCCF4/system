{ lib
, mine
, microvm
, config
, pkgs
, noxa
, ...
}:
with lib;
{
  imports = [
    ../hardware/minisforumMS1.nix

    # Users
    ../users/mx.nix

    microvm.nixosModules.host
  ]
  ++ mine.lib.optionalsIfExist [
    ../external/private/hosts/eternis.nix
  ];

  config = {
    # General settings
    networking.hostName = "eternis";
    mine.presets.primary = "server";
    networking.hostId = "806204b5";

    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

    # SSH
    services.openssh = {
      enable = true;
      ports = [
        5555
        22
      ];
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
      };
    };

    users.users.mx.openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCUipG3TQ0+yD3Nzi09x6UVQnZXlvnUkCJ4GJbfuAYqSR2pgY1jd3GtOjJHtcWC62Ydh+Z4Sus6dHTjsvDMcl8c7HNR5un0JpBpjFqZz8RLZZjYWEFvU7fU7IwZGMMOsIdje8fRgjlq96oQ8tSK3ljH6QA5/tJnPbhEy77l07juS4cY1U4X3CuQ+ULwnbpZ0TthRS9UzQHMVH+aJrY+aVMxKQ43cRzaVYCBbfriT2mlI5YvT+r1nL3sE3WXVIsagY0u9C40ASklXt/wR6b/MCMgIFruETFoIVJAnWIm0lwPQxdvCIyQLu5vjdg4Y+Tf15ZjAiD8/cxrQNxtfixPSjMp7I9Ji70EC2rDbbcZoL/mtVsec4Kp9KmZWovLnEt9GNjrnP3tZ4gnbPoxqEXNDowZ1zQkfhvp0mJNC8P504A2MR+1rC+f1gxMYg/ki1Xeyi5m5QLfOA7b7mwyzg58BqMSSBokK41ICAe+gDqBiWAP6rt/GzhavZ9xeyLRWwHhF/ZTsK2ZpYGHK18VpwG8pSpBjkZxxkeAzSFBP9lJcLK9PDhHpp6YsfE60uuA6bqanSh5HQz5UELuG14Tr5XBnY0qD8aGL73H+xMUUtDNCY48YgvIR8Tu+SzroTu5+ZlG/9CbXj0THkqqW9AAzn+lb7GVpDIWQEmGa8VE1FTLaIRd3w== mx laptop qubes vault - netcup"
    ];

    mine.persistence.enable = true;

    security.sudo.wheelNeedsPassword = false;

    # Remote unlock luks via ssh+tor
    mine.boot.remoteUnlock = true;
    mine.boot.tor.enable = true;

    #mine.vm.networks = {
    #  vm-test = {
    #    members = [ "green" "red" ];
    #    address = "10.1.0.0/24";
    #  };
    #  abc = {
    #    members = [ "red" ];
    #    address = "10.2.0.0/24";
    #  };
    #};

    #microvm = {
    #autostart = [ "log" ];
    #vms.prometheus = {
    #  restartIfChanged = true;
    #  config = {
    #    #imports = [../hardware/microvm.nix];
    #    
    #
    #  };
    #};
    #};

    microvm.vms.paperless = {
      restartIfChanged = true;
      config = {
        microvm.mem = 4096;
        imports = [ ../hardware/microvm.nix ];
        _module.args.vmName = "paperless";
        _module.args.hostConfig = config;

        microvm.shares = [{
          proto = "virtiofs";
          tag = "data";
          source = "/var/lib/microvms/paperless/data";
          mountPoint = "/paperless";
        }];

        users.users.postgres.uid = mkForce 2000;
        users.users.postgres.isSystemUser = true;
        users.users.paperless.uid = mkForce 2001;
        users.users.paperless.isSystemUser = true;

        services.postgresql.dataDir = "/paperless/database";
        services.postgresql.package = pkgs.postgresql_16;
        #    services.postgresql.authentication = pkgs.lib.mkOverride 10 ''
        #  #type database  DBuser  auth-method
        #  local all       all     trust
        #'';
        services.postgresql.identMap = ''
          # ArbitraryMapName systemUser DBUser
             superuser_map      root      postgres
             superuser_map      postgres  postgres
             # Let other names not login
             superuser_map      /^(.*)$   nouser
        '';
        services.paperless = {
          enable = true;
          consumptionDirIsPublic = true;
          dataDir = "/paperless/data";
          database.createLocally = true;
          configureTika = true;
          address = "0.0.0.0";
          port = 8000;
          settings = {
            PAPERLESS_CONSUMER_IGNORE_PATTERN = [
              ".DS_STORE/*"
              "desktop.ini"
            ];
            PAPERLESS_OCR_LANGUAGE = "deu+eng";
            PAPERLESS_OCR_USER_ARGS = {
              optimize = 1;
              pdfa_image_compression = "lossless";
            };
            PAPERLESS_URL = "https://10.20.0.1";
          };
        };

        users.users.caddy = {
          uid = mkForce 2002;
          isSystemUser = true;
        };
        services.caddy = {
          enable = true;
          dataDir = "/paperless/caddy";
          virtualHosts."192.168.0.229".extraConfig = ''
            reverse_proxy http://localhost:8000
            tls internal
            log default {
                level debug
            }
          '';
          globalConfig = ''
            default_sni 192.168.0.229
          '';
        };

        networking.firewall.allowedTCPPorts = [ 80 443 ];

        services.openssh.enable = true;
        services.openssh.settings.PermitRootLogin = "yes";
        users.users.root.password = "root";

        environment.systemPackages = with pkgs; [
          coreutils-full
          net-tools
          iproute2
          pciutils
          kitty
          caddy
          nss.tools
        ];
      };
    };
    mine.vm.networks.vm-paperless = {
      members = [ "paperless" ];
      address = "10.20.0.0/24";
      nat = true;
    };
    networking.nat.forwardPorts = [
      {
        sourcePort = 80;
        proto = "tcp";
        destination = "${(noxa.lib.net.decompose config.mine.vm.networks.vm-paperless.memberAddresses.paperless).addressNoMask}:80";
      }
      {
        sourcePort = 443;
        proto = "tcp";
        destination = "${(noxa.lib.net.decompose config.mine.vm.networks.vm-paperless.memberAddresses.paperless).addressNoMask}:443";
      }
    ];
  };
}
