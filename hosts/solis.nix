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

      usbreset = getExe' pkgs.usbutils "usbreset";
      usbResetDevices = [
        "SAKURA-X"
        "PicoScope 3000 Series PC Oscilloscope"
      ];
      reset-lab-usb = pkgs.writeShellApplication {
        name = "reset-lab-usb";
        text = ''
          /run/wrappers/bin/sudo ${usbreset} "SAKURA-X"
          /run/wrappers/bin/sudo ${usbreset} "PicoScope 3000 Series PC Oscilloscope"
        '';
      };
    in
    {
      networking.networkmanager.unmanaged = [ "interface-name:${ifaceExternal}" ];

      # General settings
      networking.hostName = "solis";
      mine.presets.primary = "workstation";
      networking.hostId = "57c565f7";

      mine.admins = [ "mx" ];
      users.groups.dialout.members = [ "mx" ];

      #mine.virtualization.virtualBox = true;
      users.groups.virtualbox.members = [ "mx" ];

      mine.persistence.enable = true;

      boot.tmp.cleanOnBoot = true;

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

      # Share the uplink with hosts plugged into the dock: DHCP + DNS + IPv4 NAT on ethDocking
      specialisation."docking-router".configuration =
        let
          iface = "ethDocking";
          address = "10.77.0.1";
          # dnscrypt-proxy's ip:port -> dnsmasq's ip#port
          toDnsmasqServer = listen:
            let m = builtins.match "\\[?([^]]*)]?:([0-9]+)" listen;
            in "${elemAt m 0}#${elemAt m 1}";
        in
        {
          networking.networkmanager.unmanaged = [ "interface-name:${iface}" ];
          networking.interfaces.${iface} = {
            useDHCP = false;
            ipv4.addresses = [{ inherit address; prefixLength = 24; }];
          };
          # upstream only starts it when the device appears; also on a live
          # switch-to-configuration into this specialisation (device already there)
          systemd.services."network-addresses-${iface}".wantedBy = [ "multi-user.target" ];
          # dnsmasq waits for the address (bind-dynamic picks it up either way)
          systemd.services.dnsmasq = {
            wants = [ "network-addresses-${iface}.service" ];
            after = [ "network-addresses-${iface}.service" ];
          };

          # no externalInterface: masquerade out of whichever uplink is active (ethMonRight, wifi)
          networking.nat = {
            enable = true;
            internalInterfaces = [ iface ];
          };

          services.dnsmasq = {
            enable = true;
            resolveLocalQueries = false;
            settings = {
              interface = iface;
              bind-dynamic = true; # ethDocking may appear later (dock plugged in)
              except-interface = "lo";
              no-resolv = true;
              # the local dnscrypt-proxy (filtered, encrypted upstream)
              server = map toDnsmasqServer config.mine.dns.listenAddresses;
              dhcp-range = [ "10.77.0.100,10.77.0.200,255.255.255.0,12h" ];
              dhcp-option = [ "option:router,${address}" "option:dns-server,${address}" ];
              dhcp-authoritative = true;
            };
          };

          networking.firewall.interfaces.${iface} = {
            allowedUDPPorts = [ 53 67 ];
            allowedTCPPorts = [ 53 ];
          };
        };

      # Remote unlock luks via ssh+tor
      mine.boot.remoteUnlock = true;
      boot.initrd.network.ssh.port = 4444;
      # ethMonRight is a usb nic in the monitor behind the usb-c dock
      boot.initrd.availableKernelModules = [ "r8152" ];
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
            reset-lab-usb
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
          commands = map
            (device: {
              command = ''${usbreset} "${device}"'';
              options = [ "NOPASSWD" ];
            })
            usbResetDevices;
        }
      ];

      nix.gc.automatic = false;

      # programs.evolution = {
      #   enable = true;
      #   plugins = with pkgs; [
      #     evolution-ews
      #   ];
      # };

      mine.desktop.hyprland.enable = true;
      mine.desktop.gnome.enable = true;
    };
}
