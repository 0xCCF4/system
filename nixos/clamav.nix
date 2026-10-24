{ config
, pkgs
, lib
, ...
}:
with lib;
{
  imports = [
    ./persistence.nix
    ./presets.nix
  ];

  options = with types; {
    mine.clamav = {
      enable = mkOption {
        type = bool;
        default = config.mine.presets.isWorkstation;
        description = "Enable ClamAV antivirus services";
      };
      accessScanning =
        let
          presets = config.mine.presets;
        in
        {
          enable = mkOption {
            type = bool;
            default = presets.isWorkstation;
            description = "Enable on-access file scanning";
          };
          homeDirectories = mkOption {
            type = listOf str;
            default = [
              "Downloads"
            ];
            description = "Directories to scan on access, relative to the home directory of each user";
          };
          directories = mkOption {
            type = listOf str;
            default = [ ];
            description = "Additional directories to scan on access. Must be absolute paths.";
          };
        };
      scanner.excludeDirectories = mkOption {
        type = listOf str;
        default = [ "/mnt2" ];
        description = "Directories to exclude from the on-demand clamdscan scan, as anchored regex patterns.";
      };
    };
  };

  config =
    let
      cfg = config.mine.clamav;

      # all non system users
      allNormalUsers = attrsets.filterAttrs (username: config: config.isNormalUser) config.users.users;
      allACScanHomeDirs = builtins.concatMap
        (
          dir: attrsets.mapAttrsToList (username: config: config.home + "/" + dir) allNormalUsers
        )
        cfg.accessScanning.homeDirectories;

      virusNotify = pkgs.writeScript "notify-all-users-of-virus" ''
        #!/bin/sh
        ALERT="Signature detected by clamav: $CLAM_VIRUSEVENT_VIRUSNAME in $CLAM_VIRUSEVENT_FILENAME"
        echo "$ALERT" | ${getExe' pkgs.coreutils "tee"} -a /var/log/clamav/clamav-virus-alerts.log
        # Send an alert to all graphical users.
        for ADDRESS in /run/user/*; do
            USERID=''${ADDRESS#/run/user/}
          /run/wrappers/bin/sudo -u "#$USERID" DBUS_SESSION_BUS_ADDRESS="unix:path=$ADDRESS/bus" ${getExe' pkgs.libnotify "notify-send"} -i dialog-warning "Virus found!" "$ALERT"
        done
      '';
    in
    mkIf cfg.enable {
      # extend directory with home scanning directories
      mine.clamav.accessScanning.directories = allACScanHomeDirs;

      security.sudo = {
        extraConfig = ''
          clamav ALL = (ALL) NOPASSWD: SETENV: ${getExe' pkgs.libnotify "notify-send"}
        '';
      };

      services.clamav.daemon = {
        enable = true;

        settings = {
          LogFile = "/var/log/clamav/clamav.log";
          ExtendedDetectionInfo = "yes";
          OnAccessMaxFileSize = "4000M";
          OnAccessIncludePath = cfg.accessScanning.directories;
          OnAccessPrevention = true;
          OnAccessExtraScanning = true;
          OnAccessExcludeUname = "clamav";
          VirusEvent = "${virusNotify}";
          User = "clamav";
        };
      };

      systemd.services.clamav-init = {
        description = "ClamAV initialization script";
        before = [ "clamav-daemon.service" ];
        requiredBy = [ "clamav-daemon.service" ];
        wantedBy = [ "multi-user.target" ];
        restartTriggers = [ "/etc/clamav/clamd.conf" ];

        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${getExe' pkgs.coreutils "install"} -d -o root -g clamav -m 0770 /var/log/clamav";
          RemainAfterExit = true;
          PrivateTmp = "yes";
          PrivateDevices = "yes";
          PrivateNetwork = "yes";
        };
      };

      services.clamav.updater.enable = true;

      systemd.services.clamav-daemon.wants = mkForce [ "clamav-freshclam-init.service" ];
      systemd.services.clamav-daemon.after = [ "clamav-freshclam-init.service" ];

      systemd.services.clamav-freshclam-init = {
        description = "ClamAV initial database download";
        before = [ "clamav-daemon.service" ];
        requires = [ "network-online.target" ];
        after = [ "network-online.target" ];
        unitConfig.ConditionPathExistsGlob = "!${config.services.clamav.daemon.settings.DatabaseDirectory}/daily.c[lv]d";

        serviceConfig = {
          inherit (config.systemd.services.clamav-freshclam.serviceConfig)
            Type ExecStart SuccessExitStatus StateDirectory User Group PrivateTmp PrivateDevices Slice;
        };
      };
      services.clamav.scanner.enable = true;

      services.clamav.scanner.scanDirectories = [
        "/"
      ];

      systemd.services.clamdscan.serviceConfig.ExecStart = mkIf config.services.clamav.scanner.enable (
        mkForce (
          concatStringsSep " " (
            [
              "${getExe' config.services.clamav.package "clamdscan"}"
              "--multiscan"
              "--fdpass"
              "--infected"
              "--allmatch"
            ]
            ++ map (dir: "--exclude-dir=^${dir}") cfg.scanner.excludeDirectories
            ++ config.services.clamav.scanner.scanDirectories
          )
        )
      );

      services.clamav.clamonacc.enable = cfg.accessScanning.enable;

      systemd.services.clamav-clamonacc = mkIf cfg.accessScanning.enable {
        serviceConfig = {
          # clamd takes a while to load its database after a (re)start; keep
          # pinging it for up to 2 minutes instead of failing on the first try
          ExecStart = mkForce "${getExe' config.services.clamav.package "clamonacc"} -F --fdpass --allmatch --wait --ping 60:2";
          ExecReload = "${getExe' pkgs.coreutils "kill"} -USR2 \$MAINPID";
          SyslogIdentifier = "av-scan";
          PrivateTmp = "yes";
          PrivateDevices = "yes";
          PrivateNetwork = "yes";
          Restart = "on-failure";
          # stay clear of the default start limit (5 starts in 10s)
          RestartSec = "10s";
        };
      };

      mine.persistence.directories = [
        "/var/lib/clamav"
      ];
    };
}
