{ config, lib, pkgs, utils, ... }:
# https://discourse.nixos.org/t/import-zpool-before-luks-with-systemd-on-boot/65400/2
{
  options = with lib; with types; {
    mine.boot.zfs-disks = mkOption {
      type = listOf str;
      description = "List of disk device paths that make up the ZFS pool.";
    };
    mine.boot.zfs-mount-folders = mkOption {
      type = listOf str;
      description = "List of ZFS datasets to mount during initrd.";
    };
  };

  config =
    let
      cfg = config.mine.boot;
    in
    {
      boot.zfs.forceImportRoot = false;

      boot.initrd = {
        # This would be a nightmare without systemd initrd
        systemd.enable = true;

        # Disable crypt import timeout - so we have enough time to enter our passphrase
        systemd.settings.Manager = {
          DefaultDeviceTimeoutSec = "infinity";
        };

        # Disable NixOS's systemd service that imports the pool
        systemd.services.zfs-import-pool.enable = false;

        systemd.services.import-pool-bare =
          let
            # Compute the systemd units for the devices in the pool
            devices = map (p: utils.escapeSystemdPath p + ".device") cfg.zfs-disks;
          in
          {
            after = [ "modprobe@zfs.service" ] ++ devices;
            requires = [ "modprobe@zfs.service" ];

            # Devices are added to 'wants' instead of 'requires' so that a
            # degraded import may be attempted if one of them times out.
            # 'cryptsetup-pre.target' is wanted because it isn't pulled in
            # normally and we want this service to finish before
            # 'systemd-cryptsetup@.service' instances begin running.
            wants = [ "cryptsetup-pre.target" ] ++ devices;
            before = [ "cryptsetup-pre.target" ];

            unitConfig.DefaultDependencies = false;
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            path = [ config.boot.zfs.package ];
            enableStrictShellChecks = true;
            script =
              let
                # Check that the FSes we're about to mount actually come from
                # our encryptionroot. If not, they may be fraudulent.
                shouldCheckFS = fs: fs.fsType == "zfs" && utils.fsNeededForBoot fs;
                checkFS = fs: ''
                  encroot="$(zfs get -H -o value encryptionroot ${fs.device})"
                  if [ "$encroot" != pool/crypt ]; then
                    echo ${fs.device} has invalid encryptionroot "$encroot" >&2
                    exit 1
                  else
                    echo ${fs.device} has valid encryptionroot "$encroot" >&2
                  fi
                '';
              in
              ''
                function cleanup() {
                  exit_code=$?
                  if [ "$exit_code" != 0 ]; then
                    zpool export pool
                  fi
                }
                trap cleanup EXIT
                zpool import -N -d /dev/disk/by-partlabel pool

                # Check that the file systems we will mount have the right encryptionroot.
                ${lib.concatStringsSep "\n" (lib.map checkFS (lib.filter shouldCheckFS config.system.build.fileSystems))}
              '';
          };

        luks.devices.credstore = {
          device = "/dev/zvol/pool/credstore";
          # 'tpm2-device=auto' usually isn't necessary, but for reasons
          # that bewilder me, adding 'tpm2-measure-pcr=yes' makes it
          # required. And 'tpm2-measure-pcr=yes' is necessary to make sure
          # the TPM2 enters a state where the LUKS volume can no longer be
          # decrypted. That way if we accidentally boot an untrustworthy
          # OS somehow, they can't decrypt the LUKS volume.
          #crypttabExtraOpts = [ "tpm2-measure-pcr=yes" "tpm2-device=auto" ];
        };
        # Adding an fstab is the easiest way to add file systems whose
        # purpose is solely in the initrd and aren't a part of '/sysroot'.
        # The 'x-systemd.after=' might seem unnecessary, since the mount                                                                                                
        # unit will already be ordered after the mapped device, but it
        # helps when stopping the mount unit and cryptsetup service to
        # make sure the LUKS device can close, thanks to how systemd
        # orders the way units are stopped.
        supportedFilesystems.ext4 = true;
        systemd.contents."/etc/fstab".text = ''
          /dev/mapper/credstore /etc/credstore ext4 defaults,x-systemd.after=systemd-cryptsetup@credstore.service 0 2
        '';
        # Add some conflicts to ensure the credstore closes before leaving initrd.
        systemd.targets.initrd-switch-root = {
          conflicts = [ "etc-credstore.mount" "systemd-cryptsetup@credstore.service" ];
          after = [ "etc-credstore.mount" "systemd-cryptsetup@credstore.service" ];
        };
        # Though, we need to make sure udev remains up while credstore is closing.
        # Orderings during stop jobs are reversed.
        systemd.services.systemd-udevd.before = [ "systemd-cryptsetup@credstore.service" ];

        # After the pool is imported and the credstore is mounted, finally
        # load the key. This uses systemd credentials, which is why the
        # credstore is mounted at '/etc/credstore'. systemd will look
        # there for a credential file called 'zfs-sysroot.mount' and
        # provide it in the 'CREDENTIALS_DIRECTORY' that is private to
        # this service. If we really wanted, we could make the credstore a
        # 'WantsMountsFor' instead and allow providing the key through any
        # of the numerous other systemd credential provision mechanisms.
        systemd.services.pool-load-key = {
          requiredBy = [ "initrd.target" ];
          before = [ "sysroot.mount" "initrd.target" ];
          requires = [ "import-pool-bare.service" ];
          after = [ "import-pool-bare.service" ];
          unitConfig.RequiresMountsFor = "/etc/credstore";
          unitConfig.DefaultDependencies = false;
          serviceConfig = {
            Type = "oneshot";
            ImportCredential = "zfs-sysroot.mount";
            RemainAfterExit = true;
            ExecStart = "${config.boot.zfs.package}/bin/zfs load-key -L file://\"\${CREDENTIALS_DIRECTORY}\"/zfs-sysroot.mount pool/crypt";
          };
        };
      };

      # All my datasets use 'mountpoint=$path', but you have to be careful
      # with this. You don't want any such datasets to be mounted via
      # 'fileSystems', because it will cause issues when
      # 'zfs-mount.service' also tries to do so. But that's only true in
      # stage 2. For the '/sysroot' file systems that have to be mounted
      # in stage 1, we do need to explicitly add them, and we need to add
      # the 'zfsutil' option. For my pool, that's the '/', '/nix', and
      # '/var' datasets.
      fileSystems = lib.genAttrs cfg.zfs-mount-folders
        (fs: {
          device = "pool/crypt/system${lib.optionalString (fs != "/") fs}";
          fsType = "zfs";
          #options = [ "zfsutil" ];
        }) // {
        "/boot" = {
          device = "PARTLABEL=ESP";
          fsType = "vfat";
          options = [ "umask=0077" ];
        };
      };
    };
}

# Initial disk setup (run once)
# set -x
# set -euo pipefail
# DEVICE=/dev/vda
# ASHIFT=12
# parted $DEVICE -- mklabel gpt
# parted $DEVICE -- mkpart ESP fat32 1MB 512MB
# parted $DEVICE -- set 1 boot on
# parted $DEVICE -- mkpart disk-main-root 512M 100%
# mkfs.fat -F32 -n BOOT "${DEVICE}1"
# zpool create -O mountpoint=none -O xattr=sa -O acltype=posixacl -o ashift=$ASHIFT pool ${DEVICE}2

# Create ZFS datasets
# zfs create -V 1GB pool/credstore
# sleep 4
# cryptsetup luksFormat /dev/zvol/pool/credstore
# cryptsetup luksOpen /dev/zvol/pool/credstore CREDSTORE
# mkfs.ext4 /dev/mapper/CREDSTORE
# mkdir -p /etc/credstore
# mount /dev/mapper/CREDSTORE /etc/credstore
# nix-shell -p openssl --run "openssl rand -out /etc/credstore/zfs-sysroot.mount 32"
# zfs create -o encryption=on -o keyformat=raw -o keylocation=file:///etc/credstore/zfs-sysroot.mount -o mountpoint=none pool/crypt
# zfs create -o mountpoint=legacy pool/crypt/system
# zfs create -o mountpoint=legacy pool/crypt/system/nix
# zfs create -o mountpoint=legacy pool/crypt/system/var
# zfs create -o mountpoint=legacy pool/crypt/system/persist
# zfs create -o mountpoint=none -o canmount=off -o reservation=64GB -o quota=64GB pool/reserved
# umount /etc/credstore
# cryptsetup luksClose CREDSTORE
# zpool export pool

# Setting up the system for nixos-install
# set -x
# set -euo pipefail
# zpool import -f -N -d /dev/disk/by-partlabel/ pool
# sleep 1
# cryptsetup luksOpen --readonly /dev/zvol/pool/credstore CREDSTORE
# mkdir -p /etc/credstore
# mount -o ro /dev/mapper/CREDSTORE /etc/credstore
# zfs load-key -L file:///etc/credstore/zfs-sysroot.mount pool/crypt
# umount /etc/credstore
# cryptsetup luksClose CREDSTORE
# mkdir -p /mnt
# mount -t zfs pool/crypt/system /mnt
# sleep 1
# mkdir -p /mnt/boot
# mkdir -p /mnt/nix
# mkdir -p /mnt/var
# mkdir -p /mnt/persist
# mount -t zfs pool/crypt/system/nix /mnt/nix
# mount -t zfs pool/crypt/system/var /mnt/var
# mount -t zfs pool/crypt/system/persist /mnt/persist
# mount /dev/vda1 /mnt/boot
# sleep 1
# nixos-install --flake .?submodules=1#lux
# umount -R /mnt
# zpool export pool
