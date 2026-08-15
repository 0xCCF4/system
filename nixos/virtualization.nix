{ inputs
, pkgs
, lib
, config
, ...
}:
with lib;
with builtins;
{
  imports = [
    ./presets.nix
    ./unfree.nix
  ];

  options.mine.virtualization =
    with types;
    let
      presets = config.mine.presets;
    in
    {
      virtualBox = mkOption {
        type = bool;
        default = false;
        description = "Enable VirtualBox support.";
      };
      virtUsers = mkOption {
        type = listOf str;
        default = [ ];
        description = "Users that should be added to the virtualization groups.";
      };
      virtualBoxExtensionPack = mkOption {
        type = bool;
        default = true;
        description = "Enable VirtualBox Extension Pack support.";
      };
      distrobox = mkOption {
        type = bool;
        default = presets.isWorkstation;
        description = "Enable Distrobox support.";
      };
      virtmanager = mkOption {
        type = bool;
        default = presets.isWorkstation;
        description = "Enable Virt-Manager support.";
      };
      flatpak = mkOption {
        type = bool;
        default = presets.isWorkstation;
        description = "Enable Flatpak support.";
      };
    };

  config =
    let
      cfg = config.mine.virtualization;

      flatpak = cfg.flatpak || cfg.distrobox;
    in
    {
      virtualisation.virtualbox.host.enable = mkDefault cfg.virtualBox;
      virtualisation.virtualbox.host.enableExtensionPack = mkDefault cfg.virtualBoxExtensionPack;
      users.extraGroups.vboxusers.members = cfg.virtUsers;

      services.flatpak.enable = mkDefault flatpak;

      virtualisation.libvirtd = {
        enable = mkDefault cfg.virtmanager;
        qemu.vhostUserPackages = with pkgs; [ virtiofsd ];
      };
      programs.virt-manager.enable = mkDefault cfg.virtmanager;
      users.extraGroups.libvirtd.members = cfg.virtUsers;

      virtualisation.podman.enable = mkDefault cfg.distrobox;
      virtualisation.podman.dockerCompat = mkDefault cfg.distrobox;
      environment.systemPackages =
        [ ]
        ++ lists.optionals cfg.distrobox [
          pkgs.distrobox
          pkgs.podman-compose
        ]
        ++ lists.optionals cfg.flatpak [
          pkgs.flatpak
          pkgs.flatpak-builder
        ]
        ++ lists.optionals cfg.virtmanager [
          pkgs.dnsmasq
        ];

      networking.firewall.trustedInterfaces = mkIf cfg.virtmanager [ "virbr0" ];

      mine.unfree.allowList = mkIf (cfg.virtualBox && cfg.virtualBoxExtensionPack) [
        "virtualbox-extpack"
      ];
    };
}
