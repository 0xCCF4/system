{ lib
, self
, config
, noxa
, ...
}:
with lib;
let
  siblingModules = removeAttrs (noxa.lib.nixDirectoryToAttr' ./.) [ "container-common" ];
in
{
  imports = attrValues siblingModules
  ++ [
    ../../hardware/netcup.nix
  ]
  ++ self.lib.optionalsIfExist [
    ../../external/private/hosts/lux.nix
  ];

  options.mine.services.matrix.domains =
    let
      domain = self.lib.requireOption "mine.info.domain" config.mine.info.domain;
    in
    {
      homeserver = mkOption {
        type = types.str;
        default = "matrix.${domain}";
        description = "Domain Synapse (client-server API + federation) is served on.";
      };
      chat = mkOption {
        type = types.str;
        default = "chat.${domain}";
        description = "Domain the self-hosted Element Web client is served on.";
      };
      admin = mkOption {
        type = types.str;
        default = "admin.${domain}";
        description = "Domain the Ketesa admin UI is served on.";
      };
      jitsi = mkOption {
        type = types.str;
        default = "meet.${domain}";
        description = "Domain the self-hosted Jitsi instance is served on.";
      };
      turn = mkOption {
        type = types.str;
        default = "turn.${domain}";
        description = ''
          Domain the TURN/STUN service (coturn) is served on.
        '';
      };
    };

  options.mine.services.matrix.enable = mkOption {
    type = types.bool;
    default = true;
    description = ''
      Master switch for the whole self-hosted Matrix stack: Synapse, the
      Element Web client, coturn, and Jitsi.
    '';
  };

  options.mine.services.matrix.enableFederation = mkOption {
    type = types.bool;
    default = false;
    description = ''
      Whether Synapse serves the federation API and accepts federation
      traffic from other homeservers.
    '';
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
