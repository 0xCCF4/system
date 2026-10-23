{ lib
, config
, ...
}:
with lib;
{
  options.home.mine.davmail = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Expose an Exchange calendar as CalDAV on localhost via DavMail. Clients
        log in with their Exchange credentials, DavMail forwards them.
      '';
    };

    url = mkOption {
      type = types.str;
      description = "EWS endpoint of the Exchange server.";
      example = "https://mail.example.org/EWS/Exchange.asmx";
    };

    folderIds = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = ''
        DavMail folder paths mapped to EWS folder ids (patched DavMail, see
        parts/patches/davmail-folder-id-map.patch). Reaches calendars shared
        one by one, without access to the owner's parent folder.
      '';
      example = {
        "/users/team@example.org/calendar/Holiday" = "AAMkAD...";
      };
    };

    caldavPort = mkOption {
      type = types.port;
      default = 1080;
      description = "Local CalDAV port of DavMail.";
    };
  };

  config =
    let
      cfg = config.home.mine.davmail;
    in
    mkIf cfg.enable {
      services.davmail = {
        enable = true;
        settings = {
          "davmail.url" = cfg.url;
          "davmail.mode" = "EWS";
          "davmail.bindAddress" = "127.0.0.1";
          "davmail.caldavPort" = cfg.caldavPort;
          # Calendar only, an empty port disables the listener.
          "davmail.imapPort" = "";
          "davmail.smtpPort" = "";
          "davmail.popPort" = "";
          "davmail.ldapPort" = "";
        } // optionalAttrs (cfg.folderIds != { }) {
          "davmail.folderIds" = concatStringsSep ";" (mapAttrsToList (path: id: "${path}=${id}") cfg.folderIds);
        };
      };
    };
}
