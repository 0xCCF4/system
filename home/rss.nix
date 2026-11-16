# Newsboat against the self-hosted Miniflux instance on lux (see hosts/lux/miniflux.nix).
#
# Miniflux owns the subscriptions and the read state, so this module writes neither `urls`
# nor `queries` (the latter asserts on a non-empty `urls`): everything comes from the
# server, and Miniflux categories arrive as Newsboat tags. Because the server is the source
# of truth, the local cache is disposable and is not persisted.
{ config
, lib
, mineSelf
, osConfig
, ...
}:
with lib;
{
  options.home.mine.rss = with types; {
    enable = mkOption {
      type = bool;
      default = mineSelf.lib.evalMissingOption osConfig.mine.presets "isWorkstation" false;
      description = ''
        Install Newsboat and read the feeds of the Miniflux instance on lux
        (`urls-source "miniflux"`). Enabled by default on workstations.

        A user needs `url` and `tokenFile` for this, and a token has to be minted for the
        host first, so a workstation user without one sets `enable = false`.
      '';
    };

    url = mkOption {
      type = nullOr str;
      default = null;
      description = ''
        Base URL of the Miniflux instance, without `/v1`: Newsboat's `miniflux-url`.
      '';
      example = "https://feeds.example.org/";
    };

    tokenFile = mkOption {
      type = nullOr str;
      default = null;
      description = ''
        File holding the API token minted for this host (an agenix secret), used as
        `miniflux-tokenfile` so the token never appears in the Nix store or in `ps`.
      '';
      example = "/run/agenix/miniflux-api-token";
    };

    autoFetch = mkOption {
      type = bool;
      default = true;
      description = ''
        Sync the local cache from Miniflux every hour through the module's systemd user
        timer. The server does the polling, so this only refreshes read state and content.
      '';
    };
  };

  config =
    let
      cfg = config.home.mine.rss;
    in
    mkIf cfg.enable {
      assertions = [
        {
          assertion = cfg.url != null;
          message = "home.mine.rss.url must be set when home.mine.rss.enable is true.";
        }
        {
          assertion = cfg.tokenFile != null;
          message = "home.mine.rss.tokenFile must be set when home.mine.rss.enable is true.";
        }
      ];

      programs.newsboat = {
        enable = true;
        extraConfig = concatStringsSep "\n" (
          [ ''urls-source "miniflux"'' ]
          ++ optional (cfg.url != null) "miniflux-url \"${cfg.url}\""
          ++ optional (cfg.tokenFile != null) "miniflux-tokenfile \"${cfg.tokenFile}\""
          ++ [
            # `s` stars the article, `b` also hands it to Miniflux's save integration
            ''miniflux-flag-star "s"''
            ''miniflux-flag-save "b"''
          ]
        );
        autoFetchArticles = {
          enable = cfg.autoFetch;
          onCalendar = "hourly";
        };
      };
    };
}
