{ lib
, config
, ...
}:
with lib;
{
  imports = [
    ./persistence.nix
  ];

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
      example = [
        "cat"
        "/run/agenix/caldav-password"
      ];
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
        # The "todos" account stores each discovered collection in its own
        # subdirectory (basePath/todos/<collection>), so todoman needs to glob
        # two levels deep to see individual lists instead of just "todos".
        glob = "*/*";
        extraConfig = ''
          date_format = "%d.%m.%Y"
          time_format = "%H:%M"
        '';
      };

      home.mine.persistence.data.directories = [
        ".local/share/vdirsyncer"
      ];

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
          collections = [
            "from a"
            "from b"
          ];
        };
      };

      # home-manager's programs.vdirsyncer only installs the package and writes the
      # config file - it runs nothing on its own, so this timer does the actual sync.
      #
      # `discover` must run before `sync`: with collections = ["from a", "from b"],
      # vdirsyncer only creates local storage dirs for collections it has cached via
      # discover. Without it, a fresh setup has no local dirs, so `sync` has nothing
      # to sync and todoman fails with "No lists found matching ...".
      #
      # `metasync` pulls each collection's displayname/color from the CalDAV server
      # into a local `displayname`/`color` file; todoman uses that as the list's
      # name (see todoman/model.py: TodoList.name_for_path), falling back to the
      # bare collection UUID otherwise.
      systemd.user.services.vdirsyncer-sync = {
        Unit.Description = "Sync CalDAV todo list via vdirsyncer";
        Service = {
          Type = "oneshot";
          ExecStart = [
            "${config.programs.vdirsyncer.package}/bin/vdirsyncer discover"
            "${config.programs.vdirsyncer.package}/bin/vdirsyncer metasync"
            "${config.programs.vdirsyncer.package}/bin/vdirsyncer sync"
          ];
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
