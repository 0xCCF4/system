{ config, lib, options, utils, pkgs, noxa, ... }: with lib; with builtins; with noxa.lib.net.types; {
  options.mine.boot.tor = with types; {
    enable = mkOption {
      type = bool;
      default = false;
      description = ''
        Advertise Tor hidden services for remote access to this machine during boot.
      '';
    };
    ports = mkOption {
      type = listOf (submodule (submod: {
        options = {
          port = mkOption {
            type = int;
            description = ''
              The advertised port number for this hidden service.
            '';
            example = 22;
          };
          bind = mkOption {
            type = ipNoMask;
            description = ''
              When a connection request arrived to the hidden service, the request is transmitted to that target address.

              Usually this is 127.0.0.1, when the service is running on the same machine.
            '';
            example = "127.0.0.1";
            default = "127.0.0.1";
          };
          bindPort = mkOption {
            type = int;
            description = ''
              When a connection request arrived to the hidden service, the request is transmitted to that target port.

              Usually this is the same port number as the advertised port.
            '';
            example = 22;
            default = submod.config.port;
          };
        };
      }));
      description = ''
        Declaration of ports to be published as Tor hidden services.
      '';
      example = [
        {
          port = 22;
        }
      ];
    };
  };

  config =
    let
      cfg = config.mine.boot.tor;

      keyfile = config.age.secrets.${noxa.lib.secrets.computeIdentifier {
        ident = "onion-service";
        module = "mine.boot";
      }};

      storeFile = file: path {
        name = baseNameOf file;
        path = file;
      };
    in
    mkIf (cfg.enable && length cfg.ports > 0) {
      noxa.secrets.def = [
        {
          ident = "onion-service";
          module = "mine.boot";
          generator.script = "tor-hidden-service";
        }
      ];

      boot.initrd = mkIf (!config.age.rekey.initialRollout) {
        secrets = {
          "/etc/tor/tor.rc" = pkgs.writeTextFile {
            name = "tor-onion-service-bootup";
            text = ''
              DataDirectory /tmp/dummy.tor/
              SOCKSPort 127.0.0.1:10050 IsolateDestAddr
              SOCKSPort 127.0.0.1:10063
              HiddenServiceDir /etc/tor/onion
              ${concatMapStrings (portCfg: ''
                HiddenServicePort ${toString portCfg.port} ${toString portCfg.bind}:${toString portCfg.bindPort}
              '') cfg.ports}
            '';
          };
          "/etc/tor/onion/hs_ed25519_secret_key" = keyfile.path;
          "/etc/tor/onion/hs_ed25519_public_key" = storeFile (noxa.lib.filesystem.withExtension keyfile.rekeyFile "pub");
          "/etc/tor/onion/hostname" = storeFile (noxa.lib.filesystem.withExtension keyfile.rekeyFile "name");
        };

        systemd = {
          storePaths = [
            "${pkgs.tor}/bin/tor"
            "${pkgs.busybox}/bin/mkdir"
            "${pkgs.busybox}/bin/chmod"
            "${pkgs.busybox}/bin/chown"
          ];

          users.tor = {
            uid = 9000;
            shell = "${pkgs.busybox}/bin/false";
            group = "nogroup";
          };

          services.tor-prepare-conf-dir = {
            wantedBy = [ "initrd.target" ];
            after = [ "initrd-nixos-copy-secrets.service" ];
            before = [ "shutdown.target" ];
            conflicts = [ "shutdown.target" ];

            unitConfig.DefaultDependencies = false;

            enableStrictShellChecks = true;
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = "yes";
            };
            script = ''
              ${pkgs.busybox}/bin/mkdir -p /tmp/dummy.tor/
              ${pkgs.busybox}/bin/chmod -R 700 /tmp/dummy.tor/
              ${pkgs.busybox}/bin/chown -R tor:nogroup /tmp/dummy.tor/

              ${pkgs.busybox}/bin/chmod -R 700 /etc/tor/
              ${pkgs.busybox}/bin/chown -R tor:nogroup /etc/tor/
            '';
          };
          services.tor = {
            wantedBy = [ "initrd.target" ];
            wants = [ "tor-prepare-conf-dir.service" ];
            after = [ "network.target" "initrd-nixos-copy-secrets.service" "tor-prepare-conf-dir.service" ];
            before = [ "shutdown.target" ];
            conflicts = [ "shutdown.target" ];
            unitConfig.DefaultDependencies = false;

            enableStrictShellChecks = true;
            serviceConfig = {
              Type = "simple";
              Restart = "on-failure";
              KillMode = "process";
              ExecStart = "${pkgs.tor}/bin/tor -f /etc/tor/tor.rc --RunAsDaemon 0";
              User = "tor";
            };
          };
        };
      };
    };
}
