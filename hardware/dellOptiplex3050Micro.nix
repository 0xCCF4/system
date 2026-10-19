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
    ./disks/disko-zfs.nix
    ./modules/efi.nix
    nixos-hardware.nixosModules.dell-optiplex-3050
  ];

  # ZFS configuration
  mine.boot.zfs-disks = [
    "/dev/disk/by-partlabel/disk-main-root"
  ];
  mine.boot.zfs-mount-folders = [
    "/"
    "/nix"
    "/var"
    "/persist"
  ];

  # Drivers
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "nvme"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];
  boot.initrd.kernelModules = [
    "e1000e" # onboard Intel I219 NIC
  ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];
  hardware.enableRedistributableFirmware = true;

  # System configuration
  nixpkgs.hostPlatform = mkDefault "x86_64-linux";
  networking.useDHCP = mkDefault true;
}
