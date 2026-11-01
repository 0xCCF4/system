{ config
, lib
, options
, utils
, pkgs
, noxa
, ...
}:
with lib;
with builtins;
{
  options.mine.boot.remoteUnlock =
    with types;
    mkOption {
      type = bool;
      default = false;
      description = ''
        Enable SSH access to the initrd for remote unlocking of LUKS volumes.
      '';
    };

  options.mine.boot.remoteUnlockTorOnly =
    with types;
    mkOption {
      type = bool;
      default = true;
      description = ''
        Only reach the initrd's SSH through the Tor hidden service (`mine.boot.tor`): sshd
        listens on loopback, where Tor delivers the connections, not on the network. The
        initrd has no firewall, otherwise its SSH is open to every network the host is on.
      '';
    };

  config =
    let
      cfg = config.mine.boot.remoteUnlock;
      admins = filterAttrs (name: _: elem name config.mine.admins) config.users.users;

      startsWith = prefix: str: substring 0 (stringLength prefix) str == prefix;

      removeRestrictionsFromKey =
        key:
        concatStringsSep " " (
          let
            splitted = (splitString " " key);
          in
          if startsWith "ssh" (head splitted) then splitted else tail splitted
        );
    in
    mkIf cfg {
      assertions = [{
        assertion = config.mine.boot.remoteUnlockTorOnly ->
          (config.mine.boot.tor.enable && any
            (p: p.bind == "127.0.0.1" && p.bindPort == config.boot.initrd.network.ssh.port)
            config.mine.boot.tor.ports);
        message = "mine.boot.remoteUnlockTorOnly: the initrd's SSH would be unreachable, it needs a mine.boot.tor port to 127.0.0.1:${toString config.boot.initrd.network.ssh.port}.";
      }];

      mine.boot.tor.ports = [
        {
          port = config.boot.initrd.network.ssh.port;
        }
      ];

      noxa.secrets.def = [
        {
          ident = "sshd";
          module = "mine.boot";
          generator.script = "ssh-keys-ed25519";
        }
      ];

      boot.initrd = {
        network = {
          enable = true;
          ssh = mkIf (!config.age.rekey.initialRollout) {
            enable = true;
            port = mkDefault 22;
            # only the admins: the initrd's sshd drops the keys' options (a root shell for
            # the unlock), a service user's key (e.g. zrb, restricted to its command) would
            # become a full login with port forwarding
            authorizedKeys = flatten (
              mapAttrsToList
                (
                  username: user: map removeRestrictionsFromKey user.openssh.authorizedKeys.keys
                )
                admins
            );
            authorizedKeyFiles = flatten (
              mapAttrsToList (username: user: user.openssh.authorizedKeys.keyFiles) admins
            );
            hostKeys = [ "/etc/ssh/host_key" ];
            extraConfig = ''
              PasswordAuthentication no
            '' + optionalString config.mine.boot.remoteUnlockTorOnly ''
              ListenAddress 127.0.0.1:${toString config.boot.initrd.network.ssh.port}
            '';
          };
        };

        secrets = mkIf (!config.age.rekey.initialRollout) {
          "/etc/ssh/host_key" =
            mkForce
              config.age.secrets.${
              noxa.lib.secrets.computeIdentifier {
                ident = "sshd";
                module = "mine.boot";
              }
              }.path;
        };

        systemd.users.root.shell = "/bin/systemd-tty-ask-password-agent";

        #systemd.storePaths = [
        #    "${pkgs.busybox}/bin/cp"
        #    "${pkgs.busybox}/bin/chmod"
        #  ];
        #
        #systemd.services.create-shell = {
        #  requiredBy = [ "sshd.service" ];
        #  before = [ "sshd.service" ];
        #  after = [
        #    "initrd-nixos-copy-secrets.service"
        #  ];
        #
        #  unitConfig.DefaultDependencies = false;
        #
        #  enableStrictShellChecks = true;
        #  serviceConfig = {
        #    Type = "oneshot";
        #  };
        #  script = ''
        #    ${pkgs.busybox}/bin/cp ${config.boot.initrd.systemd.package}/bin/systemd-tty-ask-password-agent /bin/systemd-tty-ask-password-agent-suid
        #    ${pkgs.busybox}/bin/chmod u+s /bin/systemd-tty-ask-password-agent-suid
        #  '';
        #};

        #systemd.users = mkMerge (mapAttrsToList
        #  (name: userCfg: mkIf (userCfg.isNormalUser && userCfg.enable) {
        #    "${name}" = {
        #      inherit (userCfg) uid;
        #      group = "nogroup";
        #      shell = "/bin/systemd-tty-ask-password-agent";
        #    };
        #  })
        #  config.users.users);

        #systemd.contents = mkMerge (mapAttrsToList
        #  (name: userCfg: mkIf (userCfg.isNormalUser && userCfg.enable) {
        #    "/etc/ssh/authorized_keys.d/${name}".text = concatStringsSep "\n" (
        #      config.boot.initrd.network.ssh.authorizedKeys
        #      ++ (map (file: lib.fileContents file) config.boot.initrd.network.ssh.authorizedKeyFiles)
        #      ++ config.users.users.${name}.openssh.authorizedKeys.keys
        #      ++ (map (file: lib.fileContents file) config.users.users.${name}.openssh.authorizedKeys.keyFiles)
        #    );
        #  })
        #  config.users.users);
      };
    };
}
