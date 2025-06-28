{ pkgs
, lib
, config
, impermanence
, ...
}:
with lib;
{
  imports = [
    impermanence.nixosModules.default
    ./presets.nix
  ];

  options.mine.persistence =
    let
      preset = config.modules.nixos.usage;
    in
    with types;
    {
      enable = mkOption {
        type = bool;
        default = false;
        description = "Enable the persistence module; configuring the impermanence system.";
      };
      nukeRoot = mkOption {
        type = bool;
        default = false;
        description = "Nuke the root filesystem on boot.";
      };

      rootDirectory = mkOption {
        type = str;
        description = "Root mount point of the persistent filesystem.";
        default = "/persist";
      };
      dataDirectory = mkOption {
        type = str;
        description = "Directory to store persistent data from home directories into.";
        default = "${config.mine.persistence.rootDirectory}/data";
      };
      cacheDirectory = mkOption {
        type = str;
        description = "Directory to store cache data from home directories into.";
        default = "${config.mine.persistence.rootDirectory}/cache";
      };
      systemDirectory = mkOption {
        type = str;
        description = "Directory to store system data into.";
        default = "${config.mine.persistence.rootDirectory}/system";
      };

      directories = mkOption {
        description = "List of directories to persist.";
        default = [ ];

      };
      files = mkOption {
        description = "List of files to persist.";
        default = [ ];
      };
    };

  config =
    let
      cfg = config.mine.persistence;
      presets = config.mine.presets;
    in
    lib.mkIf cfg.enable {
      fileSystems."${cfg.rootDirectory}".neededForBoot = true;

      # system.activationScripts = lib.mkIf (inputs.settings.modules.agenix) {
      #   agenixInstall.deps = [ "agenixImpermanenceFix" ];
      # 
      #   agenixImpermanenceFix = {
      #     deps = [ "agenixNewGeneration" ];
      #     text = ''
      #       echo '[agenix] impermanence fixing' 
      #       install -d -m 0755 -o 0 -g 0 "/etc/ssh"
      #       install -Dm 0400 -o 0 -g 0 "${persistence.rootDirectory}/system/etc/ssh/ssh_host_ed25519_key" "/etc/ssh/ssh_host_ed25519_key"
      #       install -Dm 0444 -o 0 -g 0 "${persistence.rootDirectory}/system/etc/ssh/ssh_host_ed25519_key.pub" "/etc/ssh/ssh_host_ed25519_key.pub"
      #       install -Dm 0400 -o 0 -g 0 "${persistence.rootDirectory}/system/etc/ssh/ssh_host_rsa_key" "/etc/ssh/ssh_host_rsa_key"
      #       install -Dm 0444 -o 0 -g 0 "${persistence.rootDirectory}/system/etc/ssh/ssh_host_rsa_key.pub" "/etc/ssh/ssh_host_rsa_key.pub"
      #     '';
      #   };
      # };

      mine.persistence.files = [
        "/etc/machine-id"
      ] ++ (builtins.concatLists (builtins.map (k: [ k.path "${k.path}.pub" ]) config.services.openssh.hostKeys));

      mine.persistence.directories = [
        "/var/log"
        "/var/lib/nixos"
        "/var/lib/systemd/coredump"
      ] ++ lists.optionals (presets.isWorkstation) [
        "/var/lib/bluetooth"
        "/var/lib/fprint"
        "/etc/NetworkManager/system-connections"
        {
          directory = "/var/lib/colord";
          user = "colord";
          group = "colord";
          mode = "750";
        }
      ];

      environment.persistence = {
        "${cfg.systemDirectory}" = {
          hideMounts = true;
          directories = cfg.directories;
          files = cfg.files;
        };
      };

      programs.fuse.userAllowOther = true;

      systemd.services = lib.mapAttrs'
        (user: data: {
          name = "ensureImpermanenceDir-${user}";
          value = {
            description = "Ensure impermanence home exist for user ${user}";
            wantedBy = [ "local-fs.target" ];
            before = [ "local-fs.target" ];
            after = [ "persist.mount" ];
            serviceConfig.Type = "oneshot";
            unitConfig.DefaultDependencies = false;
            script = ''
              install -d -m "${data.homeMode}" -o "${user}" "${persistence.dataDirectory}/home/${user}"
              install -d -m "${data.homeMode}" -o "${user}" "${persistence.cacheDirectory}/home/${user}"
            '';
          };
        })
        (lib.filterAttrs (key: value: value.isNormalUser) config.users.users);

      boot.initrd.postDeviceCommands = lib.mkIf (persistence.nukeRoot && !persistence.rootTmpfs) (
        lib.mkAfter ''
          mkdir /btrfs_tmp
          mount /dev/nixroot_vg/root /btrfs_tmp
          if [[ -e /btrfs_tmp/root ]]; then
              mkdir -p /btrfs_tmp/old_roots
              timestamp=$(date --date="@$(stat -c %Y /btrfs_tmp/root)" "+%Y-%m-%-d_%H:%M:%S")
              mv /btrfs_tmp/root "/btrfs_tmp/old_roots/$timestamp"
          fi

          delete_subvolume_recursively() {
              IFS=$'\n'
              for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
                  delete_subvolume_recursively "/btrfs_tmp/$i"
              done
              btrfs subvolume delete "$1"
          }

          for i in $(find /btrfs_tmp/old_roots/ -maxdepth 1 -mtime +30); do
              delete_subvolume_recursively "$i"
          done

          btrfs subvolume create /btrfs_tmp/root
          umount /btrfs_tmp
        ''
      );
    };
}
