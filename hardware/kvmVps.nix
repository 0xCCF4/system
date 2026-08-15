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
    ./modules/efi.nix
    (modulesPath + "/profiles/qemu-guest.nix")
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
    "ata_piix"
    "uhci_hcd"
    "virtio_pci"
    "sr_mod"
    "virtio_blk"
    "virtio_net"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];
  hardware.enableRedistributableFirmware = true;

  # System configuration
  services.qemuGuest.enable = mkDefault true;
  nixpkgs.hostPlatform = mkDefault "x86_64-linux";

  # Networking
  networking.interfaces.wan.ipv6.addresses = mkIf (config.mine.info.public.ipv6 != null) [
    {
      address = config.mine.info.public.ipv6;
      prefixLength = 64;
    }
  ];
  networking.defaultGateway6 = mkIf (config.mine.info.public.ipv6 != null) {
    address = "fe80::1";
    interface = "wan";
  };
}
