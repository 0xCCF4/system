{ config
, lib
, ...
}:
with lib;
let
  ephemeral = filterAttrs (_: container: container.ephemeral) config.containers;
  journalDirectory = name: "/var/log/containers/${name}/journal";
in
{
  # Ephemeral containers start from an empty root: their journal lives in a tmpfs and
  # their machine ID changes with every start (nixpkgs links the journal to the host only
  # for persistent containers). A fixed machine ID and /var/log/journal bound to the host
  # (persisted with /var/log) keep their logs over restarts:
  #   journalctl -M <name>                                  (running)
  #   journalctl -D /var/log/containers/<name>/journal      (also when stopped)
  options.containers = mkOption {
    type = types.attrsOf (types.submodule ({ name, config, ... }: {
      config = mkIf config.ephemeral {
        extraFlags = [ "--uuid=${substring 0 32 (hashString "sha256" "container-machine-id:${name}")}" ];
        bindMounts."/var/log/journal" = {
          hostPath = journalDirectory name;
          isReadOnly = false;
        };
        # (on the host's disk now, per container)
        config.services.journald.settings.Journal.SystemMaxUse = mkDefault "256M";
      };
    }));
  };

  config.systemd.tmpfiles.rules = mapAttrsToList (name: _: "d ${journalDirectory name} 0755 root root -") ephemeral;
}
