{ config, lib, pkgs, self, ... }: with lib; {
  options = with types; {
    mine.autoUpdate = {
      enable = mkOption {
        type = bool;
        default = false;
        description = "Enable scheduled unattended flake updates with rollback on error.";
      };
      schedule = mkOption {
        type = str;
        default = "daily";
        description = "systemd timer schedule";
      };
      inputs = mkOption {
        type = listOf str;
        default = [ ];
        description = ''
          Flake input names to update (passed to `nix flake update <names>`).
          If empty, ALL inputs are updated.
        '';
      };
      healthChecks = mkOption {
        type = listOf str;
        default = [
          ''if [ "$(systemctl --failed --no-legend | wc -l)" -ne 0 ]; then systemctl --failed --no-legend >&2; exit 1; fi''
          "systemctl is-active --quiet sshd.service"
          "systemctl is-active --quiet network-online.target"
        ];
        description = ''
          Shell commands to run as part of the post-activation health
          check, each run via `bash -c "<command>"`. A non-zero exit from
          any command means the update has failed
          and gets rolled back.
        '';
      };
      healthCheckDelaySeconds = mkOption {
        type = int;
        default = 10;
        description = ''
          Seconds to wait after activation before running health
          checks.
        '';
      };
    };
  };

  config =
    let
      cfg = config.mine.autoUpdate;

      autoUpdateScript = pkgs.writeShellApplication {
        name = "auto-update";
        runtimeInputs = [ pkgs.nix pkgs.nixos-rebuild pkgs.coreutils pkgs.systemd pkgs.bash ];
        text = ''
          HOSTNAME=${escapeShellArg config.networking.hostName}
          OLDSYSTEM="$(readlink -f /run/current-system)"

          WORKDIR="$(mktemp -d -t auto-update.XXXXXXXXXX)"
          COMMITTED=0

          finish() {
            local status=$?
            if [ "$COMMITTED" -ne 1 ]; then
              echo "[auto-update] no committed update on exit - ensuring old system is active: $OLDSYSTEM" >&2
              "$OLDSYSTEM/bin/switch-to-configuration" test || echo "[auto-update] rollback activation FAILED" >&2
            fi
            rm -rf "$WORKDIR"
            exit "$status"
          }
          trap finish EXIT TERM INT

          echo "[auto-update] old system generation: $OLDSYSTEM"
          echo "[auto-update] staging flake copy in: $WORKDIR"

          cp -r --no-preserve=mode ${self} "$WORKDIR/flake"
          chmod -R u+w "$WORKDIR/flake"

          UPDATE_INPUTS=(${concatStringsSep " " (map escapeShellArg cfg.inputs)})
          if [ "''${#UPDATE_INPUTS[@]}" -eq 0 ]; then
            echo "[auto-update] updating ALL flake inputs"
          else
            echo "[auto-update] updating flake inputs: ''${UPDATE_INPUTS[*]}"
          fi
          nix flake update --flake "$WORKDIR/flake" "''${UPDATE_INPUTS[@]}"

          echo "[auto-update] running: nixos-rebuild test"
          if ! nixos-rebuild test --flake "$WORKDIR/flake#$HOSTNAME"; then
            echo "[auto-update] nixos-rebuild test FAILED - nothing was activated" >&2
            exit 1
          fi

          echo "[auto-update] waiting ${toString cfg.healthCheckDelaySeconds}s for services to stabilize before health check"
          sleep ${toString cfg.healthCheckDelaySeconds}

          echo "[auto-update] running post-activation health checks"
          healthy=1
          # shellcheck disable=SC2016 # literal $(...) inside these single-quoted strings is intentional - each is re-evaluated later via `bash -c`
          HEALTH_CHECKS=(${concatStringsSep " " (map escapeShellArg cfg.healthChecks)})
          for check in "''${HEALTH_CHECKS[@]}"; do
            echo "[auto-update] running health check: $check"
            if ! bash -c "$check"; then
              echo "[auto-update] health check FAILED: $check" >&2
              healthy=0
            fi
          done

          if [ "$healthy" -ne 1 ]; then
            echo "[auto-update] health check failed - old system will be restored on exit" >&2
            exit 1
          fi

          echo "[auto-update] health check passed - promoting new generation"
          nixos-rebuild switch --flake "$WORKDIR/flake#$HOSTNAME"
          COMMITTED=1
          echo "[auto-update] done"
        '';
      };
    in
    mkIf cfg.enable {
      systemd.services.auto-update = {
        description = "Update flake inputs and test/switch the system, with automatic rollback";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        restartIfChanged = false;
        stopIfChanged = false;
        serviceConfig = {
          Type = "oneshot";
          ExecStart = getExe autoUpdateScript;
          TimeoutStartSec = "infinity";
          TimeoutStopSec = "infinity";
          PrivateTmp = true;
        };
      };

      systemd.timers.auto-update = {
        description = "Timer for auto-update";
        timerConfig = {
          OnCalendar = cfg.schedule;
          Persistent = true;
        };
        wantedBy = [ "timers.target" ];
      };
    };
}
