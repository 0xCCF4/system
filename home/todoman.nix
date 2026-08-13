{ lib
, config
, ...
}: with lib; {
  options.home.mine.todoman = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enable CalDAV todo-list sync via vdirsyncer + todoman.
      '';
    };

    url = mkOption {
      type = types.str;
      description = "Base URL of the CalDAV server's collection root for this user.";
      example = "https://caldav.vlan/mx/";
    };

    username = mkOption {
      type = types.str;
      description = "CalDAV username.";
    };

    passwordCommand = mkOption {
      type = types.listOf types.str;
      description = "Argv of a command that prints the CalDAV password to stdout.";
      example = [ "cat" "/run/agenix/caldav-password" ];
    };
  };

  config =
    let
      cfg = config.home.mine.todoman;
    in
    mkIf cfg.enable {
      # vdirsyncer is wired declaratively through accounts.calendar.accounts.todos below
      # (home-manager's programs.vdirsyncer module generates its config from this).
      # programs.todoman itself derives its `path` setting from accounts.calendar.basePath.
      programs.vdirsyncer.enable = true;
      programs.todoman = {
        enable = true;
        extraConfig = mkDefault ''
          date_format = "%d.%m.%Y"
        '';
      };

      accounts.calendar.basePath = ".local/share/vdirsyncer";
      accounts.calendar.accounts.todos = {
        primary = true;
        remote = {
          type = "caldav";
          url = cfg.url;
          userName = cfg.username;
          passwordCommand = cfg.passwordCommand;
        };
        vdirsyncer = {
          enable = true;
          collections = [ "from a" "from b" ];
        };
      };

      # home-manager's programs.vdirsyncer only installs the package and writes the
      # config file - it runs nothing on its own, so this timer does the actual sync.
      systemd.user.services.vdirsyncer-sync = {
        Unit.Description = "Sync CalDAV todo list via vdirsyncer";
        Service = {
          Type = "oneshot";
          ExecStart = "${config.programs.vdirsyncer.package}/bin/vdirsyncer sync";
        };
      };

      systemd.user.timers.vdirsyncer-sync = {
        Unit.Description = "Periodic vdirsyncer sync timer";
        Timer = {
          OnBootSec = "2m";
          OnUnitActiveSec = "15m";
        };
        Install.WantedBy = [ "timers.target" ];
      };
    };
}
