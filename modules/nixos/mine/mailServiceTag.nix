{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.mine.services.mailServiceTag;

  # The socket lives in /run so that the service runtime directory can hold it.
  runtimeDirectory = removePrefix "/run/" (dirOf cfg.socket);

  # Render the explicit service->tag mapping into an immutable store file.
  # Each line is key=value; `service.<localpart>` keys map a recipient
  # local-part to the tag placed in the Subject line.  The values themselves
  # (the list of services and their tags) are private data and are set from
  # external/private, not here.
  configText =
    concatStringsSep "\n"
      (
        [
          "socket=${cfg.socket}"
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
        (for example `[github]`) onto the Subject of inbound mail that does
        not claim an S/MIME or PGP signature.  Lets the owner of a catch-all
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
        Subject line of inbound mail to that address.  This list is private
        data and is meant to be set in external/private.
      '';
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          assertion = hasPrefix "/run/" cfg.socket;
          message = "mine.services.mailServiceTag.socket must be below /run/";
        }
      ];
    }

    (import ./milterService.nix {
      inherit config pkgs;
      name = "mail-service-tag";
      description = "Inbound service-subject-tagging Postfix milter";
      script = ./mailServiceTag/mail_service_tag_milter.py;
      inherit runtimeDirectory;
      environment = [ "SERVICE_TAG_CONFIG=${serviceTagConfig}" ];
    })

    {
      # Tag inbound mail after rspamd has seen it.  rspamd runs the DKIM
      # verification and the spam scanning.  Running behind rspamd therefore
      # means both see the original, untagged Subject.  Marking the entry
      # mkAfter sorts it behind the plain (rspamd) entry in mailMilter.nix's
      # aggregate.  mailMilter.nix owns the final smtpd_milters value.
      mine.services.mailMilter.milters = lib.mkAfter [ "unix:${cfg.socket}" ];
    }
  ]);
}
