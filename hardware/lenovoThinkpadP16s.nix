{ inputs
, pkgs
, lib
, config
, disko
, nixos-hardware
, modulesPath
, ...
}:
with lib;
{
  imports = [
    ./disks/disko-zfs.nix
    ./modules/efi.nix
    nixos-hardware.nixosModules.lenovo-thinkpad
    nixos-hardware.nixosModules.common-pc-ssd
    "${nixos-hardware}/common/cpu/intel/meteor-lake"
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
  hardware.logitech.wireless.enable = true;
  programs.solaar.enable = true;
  services.udev.packages = with pkgs; [ logitech-udev-rules ];
  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "thunderbolt"
    "usb_storage"
    "usbhid"
    "sd_mod"
  ];
  boot.swraid.enable = true;
  boot.swraid.mdadmConf = "PROGRAM /usr/bin/env true";
  services.lvm.boot.thin.enable = true;
  boot.kernelModules = [
    "kvm-intel"
    "dm-snapshot"
  ];
  boot.kernelParams = [
    "intel_iommu=on" # DMA protection: Thunderbolt/USB4/PCIe devices only reach memory the kernel grants (off by default for Intel in the NixOS kernel)
    "efi=disable_early_pci_dma" # no device DMA during early boot, before the IOMMU is up
  ];
  hardware.enableRedistributableFirmware = mkDefault true;
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;
  hardware.graphics.extraPackages = [ pkgs.mesa ];
  services.lvm.enable = true;
  services.fprintd.enable = true;
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = false;

  # System configuration
  nixpkgs.hostPlatform = mkDefault "x86_64-linux";
  networking.useDHCP = mkDefault true;
  powerManagement.cpuFreqGovernor = mkDefault "powersave";
  networking.networkmanager.enable = true;

  boot.binfmt.registrations.appimage = {
    wrapInterpreterInShell = false;
    interpreter = "${pkgs.appimage-run}/bin/appimage-run";
    recognitionType = "magic";
    offset = 0;
    mask = ''\xff\xff\xff\xff\x00\x00\x00\x00\xff\xff\xff'';
    magicOrExtension = ''\x7fELF....AI\x02'';
  };

  boot.binfmt.emulatedSystems = [
    "aarch64-linux"
    "riscv64-linux"
  ];
  nix.settings.extra-platforms = [
    "aarch64-linux arm-linux"
    "riscv64-linux"
  ];
}
