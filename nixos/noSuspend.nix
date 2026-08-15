{ config
, pkgs
, lib
, ...
}:
with lib;
{
  options.mine.noSuspend =
    with types;
    mkOption {
      type = bool;
      default = true;
      description = "Whether to disable system suspend.";
    };

  config = mkIf config.mine.noSuspend {
    systemd.sleep.settings.Sleep = {
      AllowSuspend = "no";
      AllowHibernation = "no";
      AllowHybridSleep = "no";
      AllowSuspendThenHibernate = "no";
    };

    systemd.targets.sleep.enable = false;
    systemd.targets.suspend.enable = false;
    systemd.targets.hibernate.enable = false;
    systemd.targets.hybrid-sleep.enable = false;
  };
}
