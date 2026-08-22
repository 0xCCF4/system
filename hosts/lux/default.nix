{ lib
, self
, config
, ...
}:
with lib;
{
  imports = [
    ../../hardware/netcup.nix
    ./net.nix
    ./mailserver.nix
    ./caddy.nix
    ./radicale.nix
    ./powerdns.nix
    ./matrix-synapse.nix
    ./matrix-coturn.nix
    ./jitsi.nix
    ./matrix-web.nix
    ./firewall.nix
  ]
  ++ self.lib.optionalsIfExist [
    ../../external/private/hosts/lux.nix
  ];

  options.mine.services.matrix.domains = {
    homeserver = mkOption {
      type = types.str;
      default = "matrix.${config.mine.info.domain}";
      description = "Domain Synapse (client-server API + federation) is served on.";
    };
    chat = mkOption {
      type = types.str;
      default = "chat.${config.mine.info.domain}";
      description = "Domain the self-hosted Element Web client is served on.";
    };
    admin = mkOption {
      type = types.str;
      default = "admin.${config.mine.info.domain}";
      description = "Domain the Ketesa admin UI is served on.";
    };
    jitsi = mkOption {
      type = types.str;
      default = "meet.${config.mine.info.domain}";
      description = "Domain the self-hosted Jitsi instance is served on.";
    };
    turn = mkOption {
      type = types.str;
      default = "turn.${config.mine.info.domain}";
      description = ''
        Domain the TURN/STUN service (coturn) is served on.
      '';
    };
  };

  config = {
    # General settings
    networking.hostName = "lux";
    mine.presets.primary = "server";
    networking.hostId = "9a5839bd";

    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
    boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = 1;
    boot.kernelModules = [
      "veth"
      "kvm"
    ];

    mine.admins = [ "mx" ];

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
        GatewayPorts = "yes";
      };
    };

    mine.persistence.enable = true;

    mine.autoUpdate.enable = true;
    mine.autoUpdate.schedule = "daily";
    mine.autoUpdate.inputs = [
      "nixpkgs"
      "nixpkgs-stable"
    ];

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
