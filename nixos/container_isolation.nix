{ config
, lib
, ...
}:
with lib;
let
  cfg = config.mine.containers;

  # as nixpkgs' nixos-containers.nix decides whether it binds the socket
  daemonSocketBound = config.nix.enable && config.nix.daemon.enable;

  userns = container: container.privateUsers == "pick" || (isInt container.privateUsers && container.privateUsers > 0);

  # agenix secrets live on a ramfs, which can't be idmapped: they are handed to the
  # container as systemd credentials instead of bind mounts
  isSecret = bind: bind.hostPath != null && hasPrefix "${config.age.secretsDir}/" bind.hostPath;

  credentialName = bind: replaceStrings [ "/" ] [ "_" ] (removePrefix "/" bind.mountPoint);

  # owner/group/mode of the secret, as agenix installs it on the host
  secretOf = bind: findFirst (secret: secret.path == bind.hostPath) null (attrValues config.age.secrets);

  bindFlag = bind:
    let
      flag = if bind.isReadOnly then "--bind-ro=" else "--bind=";
      source = if bind.hostPath != null then "${bind.hostPath}:${bind.mountPoint}" else bind.mountPoint;
    in
    "${flag}${source}:idmap";

  flags = container:
    let
      binds = attrValues container.bindMounts;
    in
    map bindFlag (filter (bind: !isSecret bind) binds)
    ++ map (bind: "--load-credential=${credentialName bind}:${bind.hostPath}") (filter isSecret binds)
    ++ container.extraFlags;
in
{
  options.mine.containers = with types; {
    userNamespaces = mkOption {
      type = bool;
      default = true;
      description = ''
        Run the NixOS containers in their own user namespace (`privateUsers = "pick"`): the
        container's root isn't the host's root. The bind mounts keep working without any
        change to the container definitions: they become idmapped mounts (the files keep
        their owners), agenix secrets (ramfs, not idmappable) are passed as systemd
        credentials and installed at the same path, with the same owner and mode.
      '';
    };

    hideNixDaemon = mkOption {
      type = bool;
      default = true;
      description = ''
        Make the host's nix-daemon socket, which NixOS bind mounts into every container,
        inaccessible inside the containers: nothing there needs it, and through it a container
        could build on the host (fixed-output derivations get the host's network namespace).
      '';
    };
  };

  # every container, also ones added later, through its submodule type
  options.containers = mkOption {
    type = types.attrsOf (types.submodule ({ config, ... }: {
      config = mkMerge [
        (mkIf (cfg.hideNixDaemon && daemonSocketBound) {
          extraFlags = [ "--inaccessible=/nix/var/nix/daemon-socket" ];
        })

        (mkIf cfg.userNamespaces {
          privateUsers = mkDefault "pick";
        })

        (mkIf (cfg.userNamespaces && userns config) {
          config =
            let
              secrets = filter isSecret (attrValues config.bindMounts);
            in
            mkIf (secrets != [ ]) {
              systemd.services.container-credentials = {
                description = "Install the secrets passed as credentials";
                wantedBy = [ "sysinit.target" ];
                before = [ "sysinit.target" ];
                after = [ "local-fs.target" ];
                unitConfig.DefaultDependencies = false;
                serviceConfig = {
                  Type = "oneshot";
                  RemainAfterExit = true;
                };
                script = concatMapStrings
                  (bind:
                    let
                      secret = secretOf bind;
                      owner = if secret != null then secret.owner else "0";
                      group = if secret != null then secret.group else "0";
                      mode = if secret != null then secret.mode else "0400";
                    in
                    # The owner is the host's (e.g. a user only the host knows, for a secret it
                    # shares with workstations): fall back to root inside the container, where
                    # such secrets are read by root anyway (e.g. LoadCredential=)
                    ''
                      install -D -o ${escapeShellArg owner} -g ${escapeShellArg group} -m ${mode} \
                        ${escapeShellArg "/run/credentials/@system/${credentialName bind}"} ${escapeShellArg bind.mountPoint} \
                      || { echo "${bind.mountPoint}: ${owner}:${group} unknown in this container, installing as root" >&2
                           install -D -o 0 -g 0 -m ${mode} \
                             ${escapeShellArg "/run/credentials/@system/${credentialName bind}"} ${escapeShellArg bind.mountPoint}; }
                    '')
                  secrets;
              };
            };
        })
      ];
    }));
  };

  config = {
    # The container's start script sources /etc/nixos-containers/<name>.conf: a later
    # EXTRA_NSPAWN_FLAGS replaces the bind flags nixpkgs generates (plain binds, which
    # under a user namespace would show every file as owned by `nobody`)
    environment.etc = mapAttrs'
      (name: container: nameValuePair "nixos-containers/${name}.conf" {
        text = mkAfter ''
          EXTRA_NSPAWN_FLAGS="${concatStringsSep " " (flags container)}"
        '';
      })
      (filterAttrs (_: container: cfg.userNamespaces && userns container) config.containers);
  };
}
