{ config
, lib
, options
, ...
}:
with lib;
let
  # journald identifies the journals by machine id, derived from the name so it is stable
  machineId = name: substring 0 32 (builtins.hashString "sha256" "microvm-machine-id:${name}");
  # microvm.machineId is qemu's `-smbios uuid=`
  # (/etc/machine-id in the microVM is the same without the dashes)
  machineUuid = name:
    let id = machineId name; in
    concatStringsSep "-" [ (substring 0 8 id) (substring 8 4 id) (substring 12 4 id) (substring 16 4 id) (substring 20 12 id) ];

  # below /var/log, which is persisted
  journalDir = name: "/var/log/microvm/${name}/journal";
in
{
  # The journal of every microVM (mine.microvm.names) is written to a directory of the
  # host (shared via virtiofs, see the microvm.nix FAQ). A microVM only sees its own
  # directory, not the host's journal. On the host (microVMs are no systemd-machined
  # machines, so `journalctl -M` does not work):
  #   journalctl -m _HOSTNAME=vm-<name>                     # by name, in the merged journal
  #   journalctl -D /var/log/microvm/<name>/journal         # only this microVM's journal
  config = optionalAttrs (options ? microvm) {
    microvm.vms = genAttrs config.mine.microvm.names (name: {
      config = {
        microvm.machineId = machineUuid name;
        microvm.shares = [
          {
            proto = "virtiofs";
            tag = "journal";
            source = journalDir name;
            mountPoint = "/var/log/journal";
          }
        ];
      };
    });

    systemd.tmpfiles.rules = concatMap
      (name: [
        "d ${journalDir name} 2755 root systemd-journal -"
        # makes the journal visible to journalctl --merge on the host
        "L+ /var/log/journal/${machineId name} - - - - ${journalDir name}/${machineId name}"
      ])
      config.mine.microvm.names;
  };
}
