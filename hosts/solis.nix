{ lib, pkgs, mine, config, ... }: with lib; {
  imports = [
    ../hardware/lenovoThinkpadP14.nix

    # Users
    ../users/mx.nix
  ] ++ mine.lib.optionalsIfExist [
    ../external/private/hosts/solis.nix
  ];

  config =
    let
      ifaceExternal = "ethMonRight";
      ifaceInternal = "ethDocking";
    in
    {
      # General settings
      networking.hostName = "solis";
      mine.presets.primary = "workstation";
      networking.hostId = "57c565f7";

      mine.persistence.enable = true;

      mine.locale.keyboardLayout = "us";

      specialisation."de-keyboard".configuration = {
        mine.locale.keyboardLayout = mkForce "de";
      };

      # Battery management
      mine.tlp.enable = true;

      home-manager.users.mx = {
        config = {
          home.mine.traits.traits = [
            "development"
            "office"
          ];
          home.mine.slack.enable = true;
          services.gromit-mpx.enable = false;
        };
      };

      security.sudo.wheelNeedsPassword = mkIf config.age.rekey.initialRollout false;

      # programs.evolution = {
      #   enable = true;
      #   plugins = with pkgs; [
      #     evolution-ews
      #   ];
      # };

      mine.desktop.hyprland.enable = true;
      mine.desktop.gnome.enable = true;

      specialisation."external-dhcp-server".configuration = {
        services.kea.dhcp4 = {
          enable = true;
          settings = {
            interfaces-config.interfaces = [ ifaceInternal ];

            lease-database = {
              name = "/var/lib/kea/dhcp4-leases.csv";
              type = "memfile";
              persist = true;
              lfc-interval = 3600;
            };

            valid-lifetime = 4000;
            renew-timer = 1000;
            rebind-timer = 2000;

            subnet4 = [
              {
                id = 1;
                subnet = "10.10.10.0/24";
                pools = [
                  {
                    pool = "10.10.10.16 - 10.10.10.128";
                  }
                ];

                option-data = [
                  {
                    name = "routers";
                    data = "10.10.10.1";
                  }
                  {
                    name = "domain-name-servers";
                    data = "9.9.9.9";
                  }
                ];
              }
            ];
          };
        };

        networking.nat = {
          enable = true;
          internalInterfaces = [ ifaceInternal ];
          externalInterface = ifaceExternal;
        };

        networking.interfaces = {
          "${ifaceInternal}" = {
            # connect to private network
            useDHCP = false;
            ipv4.addresses = [
              {
                address = "10.10.10.1";
                prefixLength = 24;
              }
              {
                address = "130.83.162.129";
                prefixLength = 29;
              }
            ];
          };
        };

        networking.firewall.allowedUDPPorts = [ 67 ]; # DHCP
      };
    };
}
