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
