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

  # todo remove, used for testing
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

    ## todo remove
    emergencyAccess = true;
  };
  #boot.initrd.secrets = {
  #  "/BOOTKEYS/boot_ssh_host_ed25519_key" = "/BOOTKEYS/boot_ssh_host_ed25519_key";
  #};
  #boot.initrd.network = {
  #  ssh = {
  #    enable = false;
  #    port = 33;
  #    hostKeys = [ "/BOOTKEYS/boot_ssh_host_ed25519_key" ];
  #    authorizedKeys = [
  #      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCUipG3TQ0+yD3Nzi09x6UVQnZXlvnUkCJ4GJbfuAYqSR2pgY1jd3GtOjJHtcWC62Ydh+Z4Sus6dHTjsvDMcl8c7HNR5un0JpBpjFqZz8RLZZjYWEFvU7fU7IwZGMMOsIdje8fRgjlq96oQ8tSK3ljH6QA5/tJnPbhEy77l07juS4cY1U4X3CuQ+ULwnbpZ0TthRS9UzQHMVH+aJrY+aVMxKQ43cRzaVYCBbfriT2mlI5YvT+r1nL3sE3WXVIsagY0u9C40ASklXt/wR6b/MCMgIFruETFoIVJAnWIm0lwPQxdvCIyQLu5vjdg4Y+Tf15ZjAiD8/cxrQNxtfixPSjMp7I9Ji70EC2rDbbcZoL/mtVsec4Kp9KmZWovLnEt9GNjrnP3tZ4gnbPoxqEXNDowZ1zQkfhvp0mJNC8P504A2MR+1rC+f1gxMYg/ki1Xeyi5m5QLfOA7b7mwyzg58BqMSSBokK41ICAe+gDqBiWAP6rt/GzhavZ9xeyLRWwHhF/ZTsK2ZpYGHK18VpwG8pSpBjkZxxkeAzSFBP9lJcLK9PDhHpp6YsfE60uuA6bqanSh5HQz5UELuG14Tr5XBnY0qD8aGL73H+xMUUtDNCY48YgvIR8Tu+SzroTu5+ZlG/9CbXj0THkqqW9AAzn+lb7GVpDIWQEmGa8VE1FTLaIRd3w== mx laptop qubes vault - netcup"
  #    ];
  #  };
  #};


  # Drivers
  # todo remove after testing debug_shell
  boot.kernelParams = [ "zfs.zfs_arc_max=12884901888" "rd.systemd.debug_shell" ];
  boot.initrd.availableKernelModules = [ "xhci_pci" "thunderbolt" "nvme" "usbhid" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ "dm-snapshot" "igc" "i40e" "mt7921e" ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];
  hardware.enableRedistributableFirmware = true;

  # System configuration
  nixpkgs.hostPlatform = mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = mkDefault config.hardware.enableRedistributableFirmware;
  networking.useDHCP = mkDefault true;
  networking.networkmanager.enable = mkDefault true;
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
  nix.settings.extra-platforms = [ "aarch64-linux arm-linux" ];
}
