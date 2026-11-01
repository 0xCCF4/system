{ config
, lib
, pkgs
, ...
}:
with lib;
let
  cfg = config.mine.qemuGuestAgent;

  allow = [
    "guest-sync-delimited"
    "guest-sync"
    "guest-ping"
    "guest-info"
    "guest-fsfreeze-status"
    "guest-fsfreeze-freeze"
    "guest-fsfreeze-freeze-list"
    "guest-fsfreeze-thaw"
    "guest-shutdown"
    "guest-get-osinfo"
    "guest-get-host-name"
    "guest-network-get-interfaces"
    "guest-get-time"
    "guest-get-timezone"
  ];
  block = [
    "guest-exec"
    "guest-exec-status"
    "guest-file-open"
    "guest-file-close"
    "guest-file-read"
    "guest-file-write"
    "guest-file-seek"
    "guest-file-flush"
    "guest-set-user-password"
    "guest-ssh-get-authorized-keys"
    "guest-ssh-add-authorized-keys"
    "guest-ssh-remove-authorized-keys"
    "guest-set-time"
    "guest-set-vcpus"
    "guest-set-memory-blocks"
    "guest-suspend-disk"
    "guest-suspend-ram"
    "guest-suspend-hybrid"
    "guest-fstrim"
  ];
in
{
  options.mine.qemuGuestAgent = with types; {
    enable = mkOption {
      type = bool;
      default = false;
      description = "Run the QEMU guest agent (the hoster's panel talks to the VM through it).";
    };

    restrict = mkOption {
      type = bool;
      default = true;
      description = ''
        Restrict the guest agent to what a hoster's panel needs: snapshots (filesystem
        freeze), shutdown, showing OS/hostname/addresses/time. The agent lets the hypervisor
        side, i.e. whoever takes over the hoster account, drive the VM: no command
        execution, file access, password or SSH key changes, clock/CPU/memory changes,
        suspend, trim. An allow-list, the block-list on top wins over it, no config file can
        add commands. Applies whenever `services.qemuGuest` is enabled.
      '';
    };
  };

  config = mkMerge [
    (mkIf cfg.enable {
      services.qemuGuest.enable = true;
    })

    (mkIf (config.services.qemuGuest.enable && cfg.restrict) {
      systemd.services.qemu-guest-agent = {
        # an empty config (qemu-ga wants a regular file), read-only in the store: no config
        # file (e.g. /etc/qemu/qemu-ga.conf) can add commands back
        environment.QGA_CONF = "${pkgs.writeText "qemu-ga.conf" ""}";
        serviceConfig.ExecStart = mkForce (concatStringsSep " " [
          "${config.services.qemuGuest.package}/bin/qemu-ga"
          "--statedir /run/qemu-ga"
          "--allow-rpcs=${concatStringsSep "," allow}"
          "--block-rpcs=${concatStringsSep "," block}"
        ]);
      };
    })
  ];
}
