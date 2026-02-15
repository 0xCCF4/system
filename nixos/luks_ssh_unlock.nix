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
            authorizedKeys = [ "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCUipG3TQ0+yD3Nzi09x6UVQnZXlvnUkCJ4GJbfuAYqSR2pgY1jd3GtOjJHtcWC62Ydh+Z4Sus6dHTjsvDMcl8c7HNR5un0JpBpjFqZz8RLZZjYWEFvU7fU7IwZGMMOsIdje8fRgjlq96oQ8tSK3ljH6QA5/tJnPbhEy77l07juS4cY1U4X3CuQ+ULwnbpZ0TthRS9UzQHMVH+aJrY+aVMxKQ43cRzaVYCBbfriT2mlI5YvT+r1nL3sE3WXVIsagY0u9C40ASklXt/wR6b/MCMgIFruETFoIVJAnWIm0lwPQxdvCIyQLu5vjdg4Y+Tf15ZjAiD8/cxrQNxtfixPSjMp7I9Ji70EC2rDbbcZoL/mtVsec4Kp9KmZWovLnEt9GNjrnP3tZ4gnbPoxqEXNDowZ1zQkfhvp0mJNC8P504A2MR+1rC+f1gxMYg/ki1Xeyi5m5QLfOA7b7mwyzg58BqMSSBokK41ICAe+gDqBiWAP6rt/GzhavZ9xeyLRWwHhF/ZTsK2ZpYGHK18VpwG8pSpBjkZxxkeAzSFBP9lJcLK9PDhHpp6YsfE60uuA6bqanSh5HQz5UELuG14Tr5XBnY0qD8aGL73H+xMUUtDNCY48YgvIR8Tu+SzroTu5+ZlG/9CbXj0THkqqW9AAzn+lb7GVpDIWQEmGa8VE1FTLaIRd3w== mx laptop qubes vault - netcup" ];
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
