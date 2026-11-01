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
  mine.qemuGuestAgent.enable = mkDefault true;
  nixpkgs.hostPlatform = mkDefault "x86_64-linux";

  # Networking, static
  assertions = [
    {
      assertion = config.mine.info.public.ipv4 != null -> config.mine.info.public.ipv4PrefixLength != null && config.mine.info.public.ipv4Gateway != null;
      message = "hardware/netcup.nix: mine.info.public.ipv4 needs ipv4PrefixLength and ipv4Gateway.";
    }
  ];
  networking.useDHCP = false;
  networking.interfaces.wan.ipv4.addresses = mkIf (config.mine.info.public.ipv4 != null) [
    {
      address = config.mine.info.public.ipv4;
      prefixLength = config.mine.info.public.ipv4PrefixLength;
    }
  ];
  networking.defaultGateway = mkIf (config.mine.info.public.ipv4 != null) {
    address = config.mine.info.public.ipv4Gateway;
    interface = "wan";
  };
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
