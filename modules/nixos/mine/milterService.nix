# Shared systemd service for one Python Postfix milter.
#
# Every milter gets its own system user, and a group of the same name.  A
# code escape inside a milter therefore loses the Postfix queue.  It also
# cannot talk to another milter's socket.  Postfix joins the milter's group
# only to connect to the socket.  The milter never joins the Postfix group.
#
# This is a plain function, not a NixOS module.  A milter module merges the
# returned attribute set into its config, so the hardening lives in one place.
{ config
, pkgs
, name
, description
, script
, environment
, user ? name
, group ? name
, runtimeDirectory
, extraGroups ? [ ]
, extraServiceConfig ? { }
,
}:
let
  # Milter code runs without a shell, so the interpreter is pinned at build
  # time with exactly the packages it imports.
  python = pkgs.python3.withPackages (ps: [ ps.pymilter ]);
in
{
  # The service user owns nothing but its socket (and its state directory).
  users.groups.${group} = { };
  users.users.${user} = {
    isSystemUser = true;
    inherit group;
    description = description;
  };

  # Postfix must be able to reach the socket in the runtime directory.
  users.users.${config.services.postfix.user}.extraGroups = [ group ];

  systemd.services.${name} = {
    inherit description;
    wantedBy = [ "multi-user.target" ];
    # The socket must exist before Postfix accepts mail.  Postfix's default
    # milter_default_action refuses mail when a milter is not available.  A
    # late start therefore costs deliveries.
    before = [ "postfix.service" ];
    after = [ "network.target" ];
    serviceConfig = {
      Type = "simple";
      User = user;
      Group = group;
      SupplementaryGroups = extraGroups;
      Environment = environment;
      ExecStart = "${python}/bin/python3 ${script}";
      RuntimeDirectory = runtimeDirectory;
      # libmilter creates the socket with 0777 & ~umask.  The umask 0007
      # yields mode 0770, so only the Postfix group can connect.
      RuntimeDirectoryMode = "0750";
      UMask = "0007";
      Restart = "on-failure";
      RestartSec = "2";

      # No privilege at all.  No capabilities, no setuid files, and a
      # read-only file system.  Only the runtime directory is writable, plus
      # whatever the caller adds through extraServiceConfig.
      NoNewPrivileges = true;
      AmbientCapabilities = [ ];
      CapabilityBoundingSet = "";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      PrivateMounts = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      ProtectClock = true;
      ProtectHostname = true;
      ProtectProc = "invisible";
      ProcSubset = "pid";
      RestrictAddressFamilies = [ "AF_UNIX" ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      SystemCallFilter = [ "@system-service" ];
      SystemCallErrorNumber = "EPERM";
      RemoveIPC = true;
    } // extraServiceConfig;
  };
}
