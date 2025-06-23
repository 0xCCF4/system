{ config
, pkgs
, lib
, ...
}:
with lib;
{
  options = with types; {
    mine.clamav = {
      enable = mkOption {
        type = bool;
        default = true;
        description = "Enable ClamAV antivirus services";
      };
      accessScanning = {
        enable = mkOption {
          type = bool;
          default = true;
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
        echo "$ALERT" | ${pkgs.coreutils}/bin/tee -a /tmp/clamav-virus-alerts.log
        # Send an alert to all graphical users.
        for ADDRESS in /run/user/*; do
            USERID=''${ADDRESS#/run/user/}
          /run/wrappers/bin/sudo -u "#$USERID" DBUS_SESSION_BUS_ADDRESS="unix:path=$ADDRESS/bus" ${pkgs.libnotify}/bin/notify-send -i dialog-warning "Virus found!" "$ALERT"
        done
      '';
    in
    mkIf cfg.enable {
      # extend directory with home scanning directories
      mine.clamav.accessScanning.directories = allACScanHomeDirs;

      security.sudo = {
        extraConfig = ''
          clamav ALL = (ALL) NOPASSWD: SETENV: ${pkgs.libnotify}/bin/notify-send
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
        wantedBy = [ "multi-user.target" ];
        restartTriggers = [ "/etc/clamav/clamd.conf" ];

        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.coreutils}/bin/install -d -o root -g clamav -m 0770 /var/log/clamav";
          RemainAfterExit = true;
          PrivateTmp = "yes";
          PrivateDevices = "yes";
          PrivateNetwork = "yes";
        };
      };

      services.clamav.updater.enable = true;
      services.clamav.scanner.enable = true;

      services.clamav.scanner.scanDirectories = [
        "/"
      ];

      systemd.services.clamav-clamonacc = lib.mkIf cfg.accessScanning.enable {
        description = "ClamAV daemon (clamonacc)";
        after = [
          "clamav-freshclam.service"
          "clamav-daemon.service"
        ];
        requires = [
          "clamav-daemon.service"
        ];
        wantedBy = [ "multi-user.target" ];
        restartTriggers = [ "/etc/clamav/clamd.conf" ];

        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.systemd}/bin/systemd-cat --identifier=av-scan ${pkgs.clamav}/bin/clamonacc --allmatch -F --fdpass";
          ExecReload = "${pkgs.coreutils}/bin/kill -USR2 $MAINPID";
          PrivateTmp = "yes";
          PrivateDevices = "yes";
          PrivateNetwork = "yes";
        };
      };
    };
}
