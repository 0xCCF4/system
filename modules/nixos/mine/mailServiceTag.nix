{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.mine.services.mailServiceTag;

  milterScript = ./mailServiceTag/milter.py;

  # Render the explicit service->tag mapping into an immutable store file.
  # Each line is key=value; `service.<localpart>` keys map a recipient
  # local-part to the tag placed in the Subject line.  The values themselves
  # (the list of services and their tags) are private data and are set from
  # external/private, not here.
  configText =
    concatStringsSep "\n" (
      [ "socket=${cfg.socket}"
        "debug=${if cfg.debug then "1" else "0"}"
      ]
      ++ lib.mapAttrsToList (localpart: tag: "service.${localpart}=${tag}") cfg.services
    ) + "\n";

  serviceTagConfig = pkgs.writeText "mail-service-tag.conf" configText;
in
{
  options.mine.services.mailServiceTag = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enable the mail-service-tag milter: prefix a recipient's service tag
        (for example `[github]`) onto the Subject of inbound mail that is not
        signed or encrypted with S/MIME or PGP.  Lets the owner of a catch-all
        alias spot unsigned mail to a known service at a glance.
      '';
    };

    socket = mkOption {
      type = types.str;
      default = "/run/mail-service-tag/mail-service-tag.sock";
      description = "Unix socket the milter listens on for Postfix.";
    };

    debug = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Write detailed decision logs to the journal.  Off by default; turn it
        on while testing and watch with
        <command>journalctl -u mail-service-tag -f</command>.
      '';
    };

    services = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = { github = "github"; aws = "aws"; };
      description = ''
        Explicit mapping from recipient local-part to the tag placed in the
        Subject line of unsigned inbound mail to that address.  This list is
        private data and is meant to be set in external/private.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Tag inbound mail AFTER rspamd has seen it.  rspamd is the only DKIM
    # verifier.  Postfix itself never checks DKIM.  So running behind rspamd
    # means the signature is verified against the original, untagged Subject
    # before we rewrite it.  It also lets rspamd scan and learn from the
    # original Subject.  Marking the entry mkAfter sorts it behind the plain
    # (rspamd) entry in mailMilter.nix's aggregate.  mailMilter.nix owns the
    # final smtpd_milters value.
    mine.services.mailMilter.milters = lib.mkAfter [ "unix:${cfg.socket}" ];

    systemd.services.mail-service-tag = {
      description = "Inbound service-subject-tagging Postfix milter";
      wantedBy = [ "multi-user.target" ];
      before = [ "postfix.service" ];
      after = [ "network.target" ];
      serviceConfig = {
        Type = "simple";
        # Postfix connects to the socket, so run as the postfix user.  This
        # milter needs no Maildir access and no capabilities.
        User = config.services.postfix.user;
        Group = config.services.postfix.group;
        Environment = [ "SERVICE_TAG_CONFIG=${serviceTagConfig}" ];
        ExecStart = ''
          ${pkgs.python3.withPackages (ps: [ ps.pymilter ])}/bin/python3 ${milterScript}
        '';
        RuntimeDirectory = "mail-service-tag";
        RuntimeDirectoryMode = "0770";
        Restart = "on-failure";
        RestartSec = "2";

        # Harden: unprivileged, no capabilities, root FS read-only.
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
        RestrictAddressFamilies = [ "AF_UNIX" ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        RemoveIPC = true;
        UMask = "0077";
      };
    };
  };
}
