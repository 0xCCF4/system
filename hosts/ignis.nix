{ lib, pkgs, config, microvm, noxa, self, ... }: with lib; {
  imports = [
    ../hardware/lenovoThinkpadL14amd.nix
  ] ++ self.lib.optionalsIfExist [
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

    security.sudo.wheelNeedsPassword = mkIf config.age.rekey.initialRollout false;

    mine.desktop.hyprland.enable = true;
    mine.desktop.gnome.enable = true;


    environment.systemPackages = with pkgs; [
      android-tools
    ];
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
    };
  };

}
