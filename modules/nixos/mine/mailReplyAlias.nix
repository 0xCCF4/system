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
      ]
      ++ lib.mapAttrsToList (_: acct: "account.${acct.login}=${acct.primary}") cfg.accounts
    ) + "\n";
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
    # mkForce replaces SNM's rspamd-only smtpd_milters with ours + rspamd.
    services.postfix.settings.main.smtpd_milters = lib.mkForce [
      "unix:${cfg.socket}"
      "unix:/run/rspamd/rspamd-milter.sock"
    ];

    systemd.tmpfiles.rules = [
      "d /run/reply-alias 0755 root root -"
    ];

    systemd.services.reply-alias-milter = {
      description = "Reply-to-alias Postfix milter";
      wantedBy = [ "multi-user.target" ];
      # Start before Postfix so the socket exists before any mail is processed.
      before = [ "postfix.service" ];
      after = [ "network.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = ''
          ${pkgs.writeShellScript "reply-alias-milter-run" ''
            cat > /etc/reply-alias.conf <<'EOF'
            ${configText}
            EOF
            exec ${pkgs.python3.withPackages (ps: [ ps.pymilter ])}/bin/python3 ${milterScript}
          ''}
        '';
        RuntimeDirectory = "reply-alias";
        RuntimeDirectoryMode = "0755";
        Restart = "on-failure";
        RestartSec = "2";
        User = "root";
      };
    };
  };
}
