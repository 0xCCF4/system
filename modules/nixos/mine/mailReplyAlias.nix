{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.mine.services.mailReplyAlias;

  # The socket lives in /run so that the service runtime directory can hold it.
  runtimeDirectory = removePrefix "/run/" (dirOf cfg.socket);

  # The unit name doubles as the service user and group name (see
  # milterService.nix).
  serviceName = "reply-alias-milter";

  # Per-milter state: the SQLite store of message-id -> alias rows.
  stateDir = "${cfg.statePath}/reply-alias";

  # Render the milter config file.  Each line is key=value.
  configText =
    concatStringsSep "\n"
      (
        [
          "socket=${cfg.socket}"
          "statefile=${stateDir}/aliases.sqlite3"
          "retentiondays=${toString cfg.retentionDays}"
          # Postfix compiles its mapFiles into /var/lib/postfix/conf and
          # symlinks /etc/postfix to it.  SNM's sender_login_maps therefore
          # uses hash:/etc/postfix/vaccounts.
          "vaccountsmap=hash:/var/lib/postfix/conf/vaccounts"
          "postmap=${config.services.postfix.package}/bin/postmap"
          "debug=${if cfg.debug then "1" else "0"}"
        ]
        ++ lib.mapAttrsToList (_: acct: "account.${acct.login}=${acct.primary}") cfg.accounts
      ) + "\n";

  # The config rendered into an immutable store file.  The milter reads it
  # from REPLY_ALIAS_CONFIG, so it never writes its own config at runtime.
  # A missing or unreadable file degrades to a harmless no-op.
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

    statePath = mkOption {
      type = types.path;
      default = "/var/lib/reply-alias";
      description = ''
        Directory for the milter's message-id -> alias store.  Point it at
        persistent storage.  A system with an ephemeral root file system, such
        as the mailserver container, must place it on a mounted path.
      '';
    };

    retentionDays = mkOption {
      type = types.ints.positive;
      default = 90;
      description = ''
        How long a recorded message-id -> alias pair is kept.  A reply to a
        message older than this is not rewritten.
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

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          assertion = hasPrefix "/run/" cfg.socket;
          message = "mine.services.mailReplyAlias.socket must be below /run/";
        }
      ];
    }

    (import ./milterService.nix {
      inherit config pkgs;
      name = serviceName;
      description = "Reply-to-alias Postfix milter";
      script = ./mailReplyAlias/reply_alias_milter.py;
      inherit runtimeDirectory;
      environment = [ "REPLY_ALIAS_CONFIG=${replyAliasConfig}" ];
      extraServiceConfig = {
        # The store is the only thing this milter writes.  Everything else is
        # read-only to it.
        ReadWritePaths = [ stateDir ];
        # `postmap` is the Postfix binary, and it enumerates the local
        # interfaces at startup through netlink.  Without these families it
        # either floods the journal with warnings or fails outright,
        # depending on the Postfix release.  The milter code itself opens no
        # sockets.
        RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" "AF_NETLINK" ];
      };
    })

    {
      # The store must exist before the service starts, because
      # ReadWritePaths needs the path to be present.
      systemd.tmpfiles.rules = [
        "d ${stateDir} 0700 ${serviceName} ${serviceName} -"
      ];

      # Rewrite before DKIM signs.  rspamd signs and verifies, and it must see
      # the rewritten From, so this milter goes ahead of rspamd's in
      # smtpd_milters.  mailMilter.nix aggregates every milter into that
      # setting, and mkBefore sorts this entry ahead of the plain (rspamd)
      # entry.
      mine.services.mailMilter.milters = lib.mkBefore [ "unix:${cfg.socket}" ];
    }
  ]);
}
