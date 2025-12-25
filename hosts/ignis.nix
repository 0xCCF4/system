{ lib, pkgs, mine, config, noxa, ... }: with lib; {
  imports = [
    ../hardware/lenovoThinkpadL14amd.nix

    # Users
    ../users/mx.nix
    ../users/games.nix
  ] ++ mine.lib.optionalsIfExist [
    ../external/private/hosts/ignis.nix
  ];

  config = {
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
      address = [ "192.168.138.205/24" ];
      privateKeyFile = config.age.secrets.${noxa.lib.secrets.computeIdentifier {
        ident = "bgl-keypair";
        module = "mine.wireguard";
      }}.path;
      autostart = false;
      peers = [
        {
          publicKey = "hMAUZ1zVQIfpgQJef5mgHb40MC7rUvsAzs0l6j8qVkQ=";
          presharedKeyFile = config.age.secrets.${noxa.lib.secrets.computeIdentifier {
            ident = "bgl-presharedkey";
            module = "mine.wireguard";
          }}.path;
          allowedIPs = [ "192.168.138.0/24" ];
          endpoint = "1pmo4cjrsego920r.myfritz.net:53841"; # ToDo: route to endpoint not automatically configured https://wiki.archlinux.org/index.php/WireGuard#Loop_routing https://discourse.nixos.org/t/solved-minimal-firewall-setup-for-wireguard-client/7577
        }
      ];
    };
  };
}
