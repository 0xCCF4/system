{ lib
, pkgs
, self
, config
, ...
}:
with lib;
{
  imports = [
    ../hardware/lenovoThinkpadP14.nix
  ]
  ++ self.lib.optionalsIfExist [
    ../external/private/hosts/solis.nix
  ];

  config =
    let
      ifaceExternal = "ethMonRight";
      ifaceInternal = "ethDocking";
    in
    {
      networking.networkmanager.unmanaged = [ "interface-name:${ifaceExternal}" ];

      # General settings
      networking.hostName = "solis";
      mine.presets.primary = "workstation";
      networking.hostId = "57c565f7";

      mine.admins = [ "mx" ];
      users.groups.dialout.members = [ "mx" ];

      mine.virtualization.virtualBox = true;
      users.groups.virtualbox.members = [ "mx" ];

      mine.persistence.enable = true;

      mine.eduroam.enable = true;

      specialisation."de-keyboard".configuration = {
        mine.locale.keyboardLayout = mkForce "de";
        mine.locale.keyboardVariant = mkForce "nodeadkeys";
      };

      # Battery management
      mine.tlp.enable = true;
      mine.noSuspend = mkDefault true;
      specialisation."suspend".configuration = {
        mine.noSuspend = false;
      };

      # Remote unlock luks via ssh+tor
      mine.boot.remoteUnlock = true;
      boot.initrd.network.ssh.port = 4444;
      # ethMonRight is a usb nic in the monitor behind the usb-c dock
      boot.initrd.availableKernelModules = [ "r8152" ];

      # TODO: remove, debug initrd networking for tor unlock
      boot.initrd.systemd.storePaths = [
        "${getExe' pkgs.iproute2 "ip"}"
        "${getExe' config.boot.initrd.systemd.package "networkctl"}"
        "${getExe' config.boot.initrd.systemd.package "journalctl"}"
      ];
      boot.initrd.systemd.services.debug-net = {
        wantedBy = [ "initrd.target" ];
        after = [ "systemd-networkd.service" ];
        before = [ "shutdown.target" ];
        conflicts = [ "shutdown.target" ];
        unitConfig.DefaultDependencies = false;
        serviceConfig = {
          Type = "simple";
          StandardOutput = "tty";
          StandardError = "tty";
          TTYPath = "/dev/console";
        };
        script = ''
          for i in 1 2 3 4; do
            sleep 20
            echo "===== debug-net round $i ====="
            ls /sys/class/net
            ${getExe' pkgs.iproute2 "ip"} -br link
            ${getExe' pkgs.iproute2 "ip"} -br addr
            ${getExe' pkgs.iproute2 "ip"} route
            ${getExe' config.boot.initrd.systemd.package "networkctl"} --no-pager list
            ${getExe' config.boot.initrd.systemd.package "journalctl"} --no-pager -n 15 -u tor -u systemd-networkd
          done
        '';
      };
      mine.boot.tor.enable = true;
      mine.boot.tor.ports = [
        {
          port = 22;
          bindPort = config.boot.initrd.network.ssh.port;
        }
      ];

      mine.zrb.backupOnShutdown = true;
      services.zrb.client.enable = true;

      home-manager.users.mx = {
        config = {
          home.mine.slack.enable = true;
          services.gromit-mpx.enable = false;

          home.packages = with pkgs; [
            picoscope
          ];
        };
      };
      services.udev.packages = with pkgs; [
        picoscope.rules
      ];
      users.groups.pico.members = [ "mx" ];
      mine.unfree.allowList = [ "picoscope" ];

      security.sudo.wheelNeedsPassword = mkIf config.age.rekey.initialRollout false;

      security.sudo.extraRules = [
        {
          users = [ "mx" ];
          commands = [
            {
              command = ''${getExe' pkgs.usbutils "usbreset"} "SAKURA-X"'';
              options = [ "NOPASSWD" ];
            }
            {
              command = ''${getExe' pkgs.usbutils "usbreset"} "PicoScope 3000 Series PC Oscilloscope"'';
              options = [ "NOPASSWD" ];
            }
          ];
        }
      ];

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
              lfc-interval = 3600; # 1 hour
            };

            valid-lifetime = 4000; # ~67 min
            renew-timer = 1000; # ~17 min
            rebind-timer = 2000; # ~33 min

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

        services.hardware.bolt.enable = true;

        networking.nat = {
          enable = true;
          internalInterfaces = [ ifaceInternal ];
          externalInterface = ifaceExternal;
        };

        networking.interfaces = {
          "${ifaceInternal}" = {
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
