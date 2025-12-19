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
  ];

  # ZFS configuration
  mine.boot.zfs-disks = [
    "/dev/disk/by-partlabel/disk-main-root"
    "/dev/disk/by-partlabel/disk-main-mirror"
  ];
  mine.boot.zfs-mount-folders = [ "/" "/nix" "/var" "/persist" ];

  # Network configuration in initrd
  boot.initrd.systemd = {
    enable = true;
    network = {
      enable = true;
      networks."enp87s0" = {
        enable = true;
        name = "enp87s0";
        DHCP = "yes";
      };
      networks."enp88s0" = {
        enable = true;
        name = "enp88s0";
        DHCP = "yes";
      };
    };
  };

  # Drivers
  boot.initrd.availableKernelModules = [ "xhci_pci" "thunderbolt" "nvme" "usbhid" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ "dm-snapshot" "igc" "i40e" "mt7921e" ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];
  hardware.enableRedistributableFirmware = true;

  # System configuration
  boot.kernelParams = [ "zfs.zfs_arc_max=12884901888" ];
  nixpkgs.hostPlatform = mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = mkDefault config.hardware.enableRedistributableFirmware;
  networking.useDHCP = mkDefault true;
  networking.networkmanager.enable = mkDefault true;
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
  nix.settings.extra-platforms = [ "aarch64-linux arm-linux" ];
}
