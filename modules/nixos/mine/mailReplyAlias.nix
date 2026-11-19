{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.mine.services.mailReplyAlias;

  # Paths to the milter script and its config file.
  milterScript = ./mailReplyAlias/milter.py;

  # Render the milter config file.  Each line is key=value.
  configText =
    concatStringsSep "\n" (
      [ "socket=${cfg.socket}"
        "storage=${cfg.storagePath}"
        # Postfix compiles its mapFiles into /var/lib/postfix/conf and symlinks
        # /etc/postfix to it; SNM's sender_login_maps uses hash:/etc/postfix/vaccounts.
        "vaccountsmap=hash:/var/lib/postfix/conf/vaccounts"
        "postmap=${config.services.postfix.package}/bin/postmap"
        "debug=${if cfg.debug then "1" else "0"}"
      ]
      ++ lib.mapAttrsToList (_: acct: "account.${acct.login}=${acct.primary}") cfg.accounts
    ) + "\n";

  # The config rendered into an immutable store file.  The milter reads it
  # from REPLY_ALIAS_CONFIG, so it never writes its own config at runtime;
  # that is what lets the service run unprivileged.  A missing or unreadable
  # file degrades to a harmless no-op (see load_config).
  replyAliasConfig = pkgs.writeText "reply-alias.conf" configText;
in
{
  options.mine.services.mailReplyAlias = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enable the reply-alias milter: automatically rewrites the envelope
        sender and From: header of outbound replies so they are sent from the
        alias the original message was delivered to (for accounts with a
        catch-all alias).
      '';
    };

    socket = mkOption {
      type = types.str;
      default = "/run/reply-alias/reply-alias.sock";
      description = "Unix socket the milter listens on for Postfix.";
    };

    debug = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Write detailed decision logs to the journal.  Off by default; turn it
        on while testing and watch with
        <command>journalctl -u reply-alias-milter -f</command>.
      '';
    };

    storagePath = mkOption {
      type = types.path;
      description = ''
        Dovecot storage root (the parent of `<domain>/<user>/mail`). Used to
        locate the delivered copy of a message to read its X-Original-To header.
      '';
    };

    accounts = mkOption {
      type = types.attrsOf (types.submodule (
        { name, ... }:
        {
          options = {
            login = mkOption {
              type = types.str;
              default = name;
              description = ''
                The SMTP login (SASL username) of this account, e.g.
                <literal>postmaster@example.com</literal>. Defaults to the
                attribute name.
              '';
            };
            primary = mkOption {
              type = types.str;
              description = "The account's primary address; never rewritten to.";
            };
          };
        }
      ));
      default = { };
      description = ''
        Accounts that may use the reply-alias feature.  Which aliases each
        account is *authorized* to send from is resolved at runtime from
        Postfix's `vaccounts` sender-login map, so no duplicate list is needed
        here.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Rewrite BEFORE DKIM signs: put our milter ahead of rspamd's in
    # smtpd_milters so the signature covers the rewritten From/envelope.
    # mailMilter.nix aggregates every milter into smtpd_milters; adding ours
    # as mkBefore sorts it ahead of the plain (rspamd) entry.
    mine.services.mailMilter.milters = lib.mkBefore [ "unix:${cfg.socket}" ];

    # The milter needs three read-only accesses: the Dovecot Maildirs (group
    # of the mail storage, `virtualMail`), and Postfix's `vaccounts` sender-
    # login map.  Running it as the postfix user with the mail-storage group
    # added covers all of them; it never needs root.
    systemd.services.reply-alias-milter = {
      description = "Reply-to-alias Postfix milter";
      wantedBy = [ "multi-user.target" ];
      # Start before Postfix so the socket exists before any mail is processed.
      before = [ "postfix.service" ];
      after = [ "network.target" ];
      serviceConfig = {
        Type = "simple";
        # Give Postfix access to the milter socket and to the `vaccounts` map
        # (via its group), and read access to the Dovecot Maildirs.
        User = config.services.postfix.user;
        Group = config.services.postfix.group;
        SupplementaryGroups = [ config.mailserver.storage.group ];
        Environment = [ "REPLY_ALIAS_CONFIG=${replyAliasConfig}" ];
        ExecStart = ''
          ${pkgs.python3.withPackages (ps: [ ps.pymilter ])}/bin/python3 ${milterScript}
        '';
        RuntimeDirectory = "reply-alias";
        # The socket Postfix connects to; group-writable so the postfix user
        # can reach it.
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
