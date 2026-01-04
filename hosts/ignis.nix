{ lib, pkgs, mine, config, noxa, microvm, ... }: with lib; {
  imports = [
    ../hardware/lenovoThinkpadL14amd.nix

    # Users
    ../users/mx.nix
    ../users/games.nix
  ] ++ mine.lib.optionalsIfExist [
    ../external/private/hosts/ignis.nix
  ];

  config = {
    services.lvm.boot.thin.enable = true;

    # General settings
    networking.hostName = "ignis";
    mine.presets.primary = "workstation";
    networking.hostId = "cf5506f0";

    mine.persistence.enable = true;

    # Battery management
    mine.tlp.enable = true;

    home-manager.users.mx = {
      config = {
        home.mine.traits.traits = [
          "development"
          "office"
        ];
      };
    };

    security.sudo.wheelNeedsPassword = mkIf config.age.rekey.initialRollout false;

    mine.desktop.hyprland.enable = true;
    mine.desktop.gnome.enable = true;


    programs.adb.enable = true;
    users.users.mx.extraGroups = [ "adbusers" "kvm" ];


    # HOMEVPN VPN
    noxa.secrets.def = [
      {
        ident = "homevpn-keypair";
        module = "mine.wireguard";
      }
      {
        ident = "homevpn-presharedkey";
        module = "mine.wireguard";
      }
    ];
    networking.wg-quick.interfaces.homevpn = {
      address = [ "192.168.200.205/24" ];
      privateKeyFile = config.age.secrets.${noxa.lib.secrets.computeIdentifier {
        ident = "homevpn-keypair";
        module = "mine.wireguard";
      }}.path;
      autostart = false;
      peers = [
        {
          publicKey = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
          presharedKeyFile = config.age.secrets.${noxa.lib.secrets.computeIdentifier {
            ident = "homevpn-presharedkey";
            module = "mine.wireguard";
          }}.path;
          allowedIPs = [ "192.168.200.0/24" ];
          endpoint = "vpn.example.net:51820"; # ToDo: route to endpoint not automatically configured https://wiki.archlinux.org/index.php/WireGuard#Loop_routing https://discourse.nixos.org/t/solved-minimal-firewall-setup-for-wireguard-client/7577
        }
      ];
    };
  };

}
