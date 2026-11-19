{ lib, config, ... }:
with lib;
let
  cfg = config.mine.services.mailMilter;
in
{
  options.mine.services.mailMilter = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Central ordered list of Postfix milters.  Each milter module adds its
        socket to `milters`, tagging its whole list with mkBefore or mkAfter
        to control position.  Plain (untagged) lists sit between the before
        and after groups.
      '';
    };

    milters = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Postfix `smtpd_milters` socket definitions, in enforced order.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Own the postfix setting with mkForce.  nixos-mailserver also declares
    # smtpd_milters as a plain value (mail-server/postfix.nix), and the
    # oneOf freeform type holds exactly one definition.  This aggregation is
    # therefore the single forced source; the rspamd milter is listed here
    # explicitly by the mailserver container.
    services.postfix.settings.main.smtpd_milters = lib.mkForce cfg.milters;
  };
}
