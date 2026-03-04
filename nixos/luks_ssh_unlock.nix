{ config, lib, options, utils, pkgs, noxa, ... }: with lib; with builtins; {
  options.mine.boot.remoteUnlock = with types; mkOption {
    type = bool;
    default = false;
    description = ''
      Enable SSH access to the initrd for remote unlocking of LUKS volumes.
    '';
  };

  config =
    let
      cfg = config.mine.boot.remoteUnlock;
    in
    mkIf cfg {
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
            authorizedKeys = flatten (mapAttrsToList (username: user: user.openssh.authorizedKeys.keys) config.users.users);
            authorizedKeyFiles = flatten (mapAttrsToList (username: user: user.openssh.authorizedKeys.keyFiles) config.users.users);
            hostKeys = [ "/etc/ssh/host_key" ];
            extraConfig = ''
              PasswordAuthentication no
            '';
          };
        };

        secrets = mkIf (!config.age.rekey.initialRollout) {
          "/etc/ssh/host_key" = mkForce config.age.secrets.${noxa.lib.secrets.computeIdentifier {
            ident = "sshd";
            module = "mine.boot";
          }}.path;
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
