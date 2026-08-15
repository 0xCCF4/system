{ config
, pkgs
, lib
, self
, osConfig
, ...
}:
with lib;
{
  imports = [
    ./persistence.nix
  ];

  options.home.mine.frostx = with types; {
    enable = mkOption {
      type = bool;
      default = self.lib.evalMissingOption osConfig.mine.presets "isWorkstation" false;
      description = "Enable frostx";
    };

    package = mkOption {
      type = pkgs.lib.types.package;
      default = pkgs.frostx;
      description = "The frostx package to use.";
    };

    autoScanDaily = mkOption {
      type = bool;
      default = true;
      description = "Whether to automatically scan for new projects daily.";
    };

    autoRunOnStartup = mkOption {
      type = bool;
      default = true;
      description = "Whether to automatically run frostx on startup.";
    };
  };

  config =
    let
      cfg = config.home.mine.frostx;
    in
    lib.mkIf cfg.enable {
      home.mine.persistence.cache.directories = [
        ".local/share/frostx"
      ];

      home.mine.persistence.data.directories = [
        ".config/frostx"
      ];

      home.packages = [ cfg.package ];

      systemd.user.timers.frostx-scan = mkIf cfg.autoScanDaily {
        Unit.Description = "Daily scan for new frostx projects";
        Timer = {
          OnCalendar = "monthly";
          Persistent = true;
          Unit = "frostx-scan.service";
        };
        Install.WantedBy = [ "timers.target" ];
      };

      systemd.user.services.frostx-scan = mkIf cfg.autoScanDaily {
        Unit.Description = "Scan for new frostx projects";

        Service = {
          Type = "oneshot";
          ExecStart = "${getExe cfg.package} projects add --scan \"$HOME/Documents\"";
        };
      };

      programs.fish.interactiveShellInit = mkIf cfg.autoRunOnStartup ''
        ${getExe cfg.package} projects run --daily
      '';

      programs.bash.bashrcExtra = mkIf cfg.autoRunOnStartup ''
        ${getExe cfg.package} projects run --daily
      '';

      programs.zsh.initContent = mkIf cfg.autoRunOnStartup ''
        ${getExe cfg.package} projects run --daily
      '';
    };
}
