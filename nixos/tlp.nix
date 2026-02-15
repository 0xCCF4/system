{ pkgs
, lib
, config
, ...
}:
with lib; with builtins;
{
  options.mine.tlp = with types;
    {
      enable = mkOption {
        type = bool;
        default = false;
        description = "Use tlp to manage the power of the system.";
      };
      stopCharging = mkOption {
        type = int;
        default = 80;
        description = "The maximum charge of the battery.";
      };
      startCharging = mkOption {
        type = int;
        default = 40;
        description = "The minimum charge of the battery.";
      };
      maxCPUPerfOnBattery = mkOption {
        type = int;
        default = 20;
        description = "The maximum CPU performance percentage when on battery.";
      };
    };

  config =
    let
      cfg = config.mine.tlp;
    in
    lib.mkIf cfg.enable {
      services.power-profiles-daemon.enable = mkOverride 800 false;
      services.tlp = {
        enable = mkDefault true;
        settings = {
          CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
          CPU_ENERGY_PERF_POLICY_ON_BAT = "power";

          PLATFORM_PROFILE_ON_AC = "performance";
          PLATFORM_PROFILE_ON_BAT = "low-power";

          CPU_BOOST_ON_AC = 1;
          CPU_BOOST_ON_BAT = 0;

          CPU_HWP_DYN_BOOST_ON_AC = 1;
          CPU_HWP_DYN_BOOST_ON_BAT = 0;

          RUNTIME_PM_ON_AC = "auto";
          RUNTIME_PM_ON_BAT = "auto";

          WIFI_PWR_ON_AC = "on";
          WIFI_PWR_ON_BAT = "on";

          CPU_SCALING_GOVERNOR_ON_AC = "performance";
          CPU_SCALING_GOVERNOR_ON_BAT = "powersave";

          CPU_MIN_PERF_ON_AC = 0;
          CPU_MAX_PERF_ON_AC = 100;
          CPU_MIN_PERF_ON_BAT = 0;
          CPU_MAX_PERF_ON_BAT = cfg.maxCPUPerfOnBattery;

          START_CHARGE_THRESH_BAT0 = mkDefault cfg.startCharging;
          STOP_CHARGE_THRESH_BAT0 = mkDefault cfg.stopCharging;

          DEVICES_TO_DISABLE_ON_STARTUP = "bluetooth";
        };
      };
    };
}
