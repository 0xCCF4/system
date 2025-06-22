{ inputs
, pkgs
, lib
, config
, disko
, nixos-hardware
, ...
}:
with lib;
{
  imports = [
    disko.nixosModules.disko
    (import ./disks/disko-impermanence.nix {
      device = "/dev/nvme0n1";
      rootTmpfs = (config.mine.persistence.enable or false) && (config.mine.persistence.rootTmpfs or false);
    })
    nixos-hardware.nixosModules.lenovo-thinkpad-l14-amd
  ];

  nixpkgs.hostPlatform = mkDefault "x86_64-linux";

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
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [
    "kvm-amd"
    "dm-snapshot"
  ];
  boot.extraModulePackages = [ ];
  swapDevices = [ ];
  networking.useDHCP = mkDefault true;

  powerManagement.cpuFreqGovernor = mkDefault "powersave";
  hardware.enableRedistributableFirmware = mkDefault true;
  hardware.cpu.amd.updateMicrocode = mkDefault true;
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  networking.networkmanager.enable = true;
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;
  hardware.graphics.extraPackages = [ pkgs.mesa ];
  services.lvm.enable = true;
  services.lvm.boot.thin.enable = true;
  services.fprintd.enable = true;
  services.xserver.videoDrivers = [ "amdgpu" ];

  boot.binfmt.registrations.appimage = {
    wrapInterpreterInShell = false;
    interpreter = "${pkgs.appimage-run}/bin/appimage-run";
    recognitionType = "magic";
    offset = 0;
    mask = ''\xff\xff\xff\xff\x00\x00\x00\x00\xff\xff\xff'';
    magicOrExtension = ''\x7fELF....AI\x02'';
  };

  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
  nix.settings.extra-platforms = [ "aarch64-linux arm-linux" ];
}
