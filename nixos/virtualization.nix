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
        default = false;
        description = "Enable Distrobox support.";
      };
      virtmanager = mkOption {
        type = bool;
        default = presets.isWorkstation;
        description = "Enable Virt-Manager support.";
      };
      flatpak = mkOption {
        type = bool;
        default = false;
        description = "Enable Flatpak support.";
      };
    };

  config =
    let
      cfg = config.mine.virtualization;

      flatpak = cfg.flatpak || cfg.distrobox;
      podman = cfg.distrobox || config.mine.presets.isWorkstation;
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

      virtualisation.podman.enable = mkDefault podman;
      virtualisation.podman.dockerCompat = mkDefault podman;
      environment.systemPackages =
        [ ]
        ++ lists.optionals cfg.distrobox [
          pkgs.distrobox
        ] ++ lists.optionals podman [
          pkgs.podman-compose
        ]
        ++ lists.optionals cfg.flatpak [
          pkgs.flatpak
          pkgs.flatpak-builder
        ]
        ++ lists.optionals cfg.virtmanager [
          pkgs.dnsmasq
        ];

      # libvirt's default NAT network: its VMs only need DNS and DHCP from the host (libvirt's
      # dnsmasq), not every port (a VM may run untrusted software)
      networking.firewall.interfaces.virbr0 = mkIf cfg.virtmanager {
        allowedUDPPorts = [ 53 67 ];
        allowedTCPPorts = [ 53 ];
      };

      # ... and libvirt NATs them out of every interface: not into the fleet through the
      # host's WireGuard tunnels (they would appear as the host's tunnel address)
      networking.nftables.tables.libvirt-vm-guard = mkIf cfg.virtmanager {
        family = "inet";
        content =
          let
            tunnels = attrNames config.networking.wireguard.interfaces
              ++ attrNames config.networking.wg-quick.interfaces;
          in
          ''
            chain forward {
              type filter hook forward priority filter - 1; policy accept;
              ${optionalString (tunnels != [ ]) ''
                iifname "virbr0" oifname { ${concatMapStringsSep ", " (t: ''"${t}"'') tunnels} } limit rate 6/minute burst 5 packets log prefix "libvirt-vm-guard: " level warn
                iifname "virbr0" oifname { ${concatMapStringsSep ", " (t: ''"${t}"'') tunnels} } drop
              ''}
            }
          '';
      };

      mine.unfree.allowList = mkIf (cfg.virtualBox && cfg.virtualBoxExtensionPack) [
        "virtualbox-extpack"
      ];
    };
}
