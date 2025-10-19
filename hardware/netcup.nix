{ inputs
, pkgs
, lib
, config
, modulesPath
, disko
, ...
}:
with lib;
{
  imports = [
    ./disks/disko-zfs.nix
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  # ZFS configuration
  mine.boot.zfs-disks = [
    "/dev/disk/by-partlabel/disk-main-root"
  ];
  mine.boot.zfs-mount-folders = [ "/" "/nix" "/var" ];

  # Bootloader configuration
  boot.loader.grub = {
    enable = true;
    zfsSupport = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    mirroredBoots = [
      { devices = [ "nodev" ]; path = "/boot"; }
    ];
  };
  boot.loader.efi.canTouchEfiVariables = false;

  # Drivers
  boot.initrd.availableKernelModules = [ "ata_piix" "uhci_hcd" "virtio_pci" "sr_mod" "virtio_blk" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];
  hardware.enableRedistributableFirmware = true;

  # System configuration
  boot.kernelParams = [ "rd.systemd.debug_shell" ];
  boot.initrd.systemd.emergencyAccess = true;

  services.qemuGuest.enable = mkDefault true;
  nixpkgs.hostPlatform = mkDefault "x86_64-linux";
}
