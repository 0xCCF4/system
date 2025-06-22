{ inputs
, pkgs
, lib
, config
, nixos-hardware
, ...
}:
with lib;
{
  imports = [
    nixos-hardware.nixosModules.raspberry-pi-4
  ];

  config = {
    nixpkgs.hostPlatform = mkDefault "aarch64-linux";

    hardware.raspberry-pi."4" = { };

    boot = {
      kernelPackages = pkgs.linuxKernel.packages.linux_rpi4;
      initrd.availableKernelModules = [
        "xhci_pci"
        "usbhid"
        "usb_storage"
      ];
      loader = {
        grub.enable = false;
        generic-extlinux-compatible.enable = true;
      };
    };

    fileSystems = {
      "/" = {
        device = "/dev/disk/by-label/NIXOS_SD";
        fsType = "ext4";
        options = [ "noatime" ];
      };
    };

    systemd.network.links."10-eth" = {
      matchConfig.PermanentMACAddress = "d8:3a:dd:80:ee:81";
      linkConfig.Name = "eth0";
    };

    hardware.enableRedistributableFirmware = true;
  };

}
