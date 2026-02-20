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
    nixos-hardware.nixosModules.lenovo-thinkpad-l14-amd
  ];

  # ZFS configuration
  mine.boot.zfs-disks = [
    "/dev/disk/by-partlabel/disk-main-root"
  ];
  mine.boot.zfs-mount-folders = [ "/" "/nix" "/var" "/persist" ];

  # Drivers
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
  boot.kernelModules = [
    "kvm-amd"
    "dm-snapshot"
  ];
  hardware.enableRedistributableFirmware = mkDefault true;
  hardware.cpu.amd.updateMicrocode = mkDefault true;
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;
  hardware.graphics.extraPackages = [ pkgs.mesa ];
  services.lvm.enable = true;
  services.fprintd.enable = true;
  services.xserver.videoDrivers = [ "amdgpu" ];
  hardware.bluetooth.enable = true;

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

  boot.binfmt.emulatedSystems = [ "aarch64-linux" "riscv64-linux" ];
  nix.settings.extra-platforms = [ "aarch64-linux arm-linux" "riscv64-linux" ];
}
