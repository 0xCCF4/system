{ zrb
, pkgs
, lib
, noxaHost
, config
, nodes
, ...
}:
with lib;
{

  imports = [
    zrb.nixosModules.noxa
  ];

  options = with types; {
    mine.zrb = {
      backupNode = mkOption {
        type = nullOr types.str;
        default = "eternis";
        description = "The node to backup to. If null, the zrb client will be disabled.";
      };
      backupServerInstance = mkOption {
        type = nullOr types.str;
        default = "primary";
        description = "The server instance to backup to.";
      };
      backupSSH = mkOption {
        type = nullOr types.str;
        default =
          if (config.mine.zrb.backupNode != null) then "${config.mine.zrb.backupNode}.vlan" else null;
        description = "The SSH host to connect to for backups.";
      };
      backupOnShutdown = mkOption {
        type = bool;
        default = false;
        description = "Whether to run a backup on shutdown.";
      };
    };
  };

  config =
    let
      zrbUsers =
        (optionals (config.services.zrb.client.enable && config.services.zrb.client.createUser) [
          config.services.zrb.client.user
        ])
        ++ (flatten (
          mapAttrsToList
            (
              instanceName: data: optionals (data.enable && data.createUser) [ data.user ]
            )
            config.services.zrb.server
        ));
    in
    {
      services.zrb.client = {
        enable = mkIf (config.mine.zrb.backupNode != null) (mkDefault true);
        sourceName = mkDefault noxaHost;

        remotes.primary = {
          noxa = {
            enable = true;
            toNode = config.mine.zrb.backupNode;
            serverInstance = config.mine.zrb.backupServerInstance;
          };
          zfsSendOpts = [ "-Lec" ];
        };

        datasets = {
          "pool/crypt/system/persist".primary = "tank/backups/zrb/${config.services.zrb.client.sourceName}";
        };

        retention = {
          recent = mkDefault 7;
          weeklyForDays = mkDefault 30;
          monthlyForDays = mkDefault 365;
        };

        jobs.daily = {
          onCalendar = "daily";
          datasets = [ "pool/crypt/system/persist" ];
        };

        prune.onCalendar = "weekly";
      };

      services.zrb.server.primary = {
        noxa.enable = true;
        retention = {
          recent = 14;
          weeklyForDays = 60;
          monthlyForDays = 730;
        };

        prune.onCalendar = "weekly";
      };

      # add home manager managed zrb
      mine.fakeUsers = zrbUsers;

      users.users = mkMerge (
        map
          (
            userName:
            let
              userModule = users.${userName};
            in
            {
              "${userName}" = {
                createHome = true;
                home = mkDefault "/tmp/.tmp-zrb-home-${userName}";
                linger = true;
              };
            }
          )
          zrbUsers
      );

      ssh.grants = mkIf (config.mine.zrb.backupNode != null && config.services.zrb.client.enable) {
        zrb-primary.to.hostname = config.mine.zrb.backupSSH;
      };

      systemd.services."zrb-backup-on-shutdown" = mkIf config.mine.zrb.backupOnShutdown {
        description = "Shutdown hook ZRB backup";

        wantedBy = [ "multi-user.target" ];

        after = [
          "network-online.target"
          "local-fs.target"
          "wireguard-cloud-admin.service"
        ];
        wants = [
          "network-online.target"
          "local-fs.target"
          "wireguard-cloud-admin.service"
        ];

        serviceConfig =
          let
            dailyService = config.systemd.services."zrb-send-daily";
          in
          {
            Type = "oneshot";

            # Runs during shutdown
            ExecStop = "${
              pkgs.writeShellApplication {
                name = "zrb-backup-on-shutdown";
                text = ''
                  current_vt=$(cat /sys/class/tty/tty0/active)
                  current_vt=''${current_vt#tty}
                  trap '${pkgs.kbd}/bin/chvt "$current_vt" || true' EXIT

                  ${pkgs.kbd}/bin/chvt 8 || true
                  sleep 0.2

                  /run/wrappers/bin/sudo -u ${dailyService.serviceConfig.User} -n ${dailyService.serviceConfig.ExecStart} --tui || true

                  sleep 1
                  exit 0
                '';
              }
            }/bin/zrb-backup-on-shutdown";

            RemainAfterExit = true;

            # WatchdogSec/NotifyAccess don't apply here: this unit has no ExecStart, only
            # ExecStop, so there's no "main process" phase for systemd's watchdog to monitor
            # (confirmed empirically: WatchdogTimestamp never gets set during ExecStop).
            # TimeoutStopSec is the only mechanism that actually bounds ExecStop's runtime.
            TimeoutStopSec = "30min";

            StandardOutput = "tty";
            StandardError = "tty";
            TTYPath = "/dev/tty8";
            TTYReset = "yes";
          };

        before = [
          "shutdown.target"
          "poweroff.target"
          "umount.target"
        ];

        conflicts = [
          "shutdown.target"
          "poweroff.target"
        ];
      };
    };
}
