{ lib
, pkgs
, config
, microvm
, noxa
, self
, ...
}:
with lib;
{
  imports = [
    ../hardware/lenovoThinkpadL14amd.nix
  ]
  ++ self.lib.optionalsIfExist [
    ../external/private/hosts/ignis.nix
  ];

  config = {
    services.lvm.boot.thin.enable = true;

    mine.admins = [ "mx" ];
    mine.users = [ "games" ];

    # General settings
    networking.hostName = "ignis";
    mine.presets.primary = "workstation";
    networking.hostId = "cf5506f0";

    mine.persistence.enable = true;

    # Battery management
    mine.tlp.enable = true;

    mine.desktop.hyprland.enable = true;
    mine.desktop.gnome.enable = true;

    mine.eduroam.enable = true;

    environment.systemPackages = with pkgs; [
      android-tools
    ];
    users.users.mx.extraGroups = [
      "adbusers"
      "kvm"
    ];

    # Luks remote unlock via ssh+tor
    mine.boot.remoteUnlock = true;
    boot.initrd.network.ssh.port = 4444;
    mine.boot.tor.enable = true;
    mine.boot.tor.ports = [
      {
        port = 22;
        bindPort = config.boot.initrd.network.ssh.port;
      }
    ];
    services.zrb.client.jobs.daily.enable = false; # until we have a full root backup

    mine.virtualization.virtmanager = true;
    networking = {
      firewall = {
        enable = true;
        interfaces = {
          virbr0 = {
            allowedUDPPorts = [
              53
              67
            ];
          };
        };
      };
      nat = {
        enable = true;
        internalInterfaces = [ "virbr0" ];
      };
    };

    # BGL VPN
    noxa.secrets.def = [
      {
        ident = "bgl-keypair";
        module = "mine.wireguard";
      }
      {
        ident = "bgl-presharedkey";
        module = "mine.wireguard";
      }
    ];
    networking.wg-quick.interfaces.bgl = {
      address = [ "192.168.138.206/24" ];
      privateKeyFile =
        config.age.secrets.${
        noxa.lib.secrets.computeIdentifier {
          ident = "bgl-keypair";
          module = "mine.wireguard";
        }
        }.path;
      autostart = false;
    };

    specialisation.selinux.configuration = {
      #security.selinux.enable = true;
    };

    # TEMPORARY: route all queries for lux's domain directly to lux's own
    # public IPv4 instead of the normal upstream DNS path, to test the new
    # Matrix records without waiting on public DNS propagation. Remove once
    # no longer needed.
    # Commented out: was masking that johmat.de's registrar-level NS
    # delegation still points at Strato (docks06/shades12.rzone.de), not lux.
    /*
      services.resolved.dnsDelegates.lux.Delegate = {
      DNS = [
        self.nixosConfigurations.lux.config.mine.info.public.ipv4
        self.nixosConfigurations.lux.config.mine.info.public.ipv6
      ];
      Domains = [ "~${self.nixosConfigurations.lux.config.mine.info.domain}" ];
      };
    */
  };
}
