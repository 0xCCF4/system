# Newsboat against the self-hosted Miniflux instance on lux (see hosts/lux/miniflux.nix).
#
# Miniflux owns the subscriptions and the read state, so this module writes neither `urls`
# nor `queries` (the latter asserts on a non-empty `urls`): everything comes from the
# server, and Miniflux categories arrive as Newsboat tags. Because the server is the source
# of truth, the local cache is disposable: it is persisted as a cache (kept across reboots,
# not backed up).
{ config
, lib
, pkgs
, mineSelf
, osConfig
, ...
}:
with lib;
{
  imports = [
    ./persistence.nix
  ];

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

      # `feeds-refresh`: makes Miniflux fetch all feeds now (Newsboat's reload only syncs what
      # Miniflux already has); the token reaches curl on stdin, never on a command line
      home.packages = mkIf (cfg.url != null && cfg.tokenFile != null) [
        (pkgs.writeShellApplication {
          name = "feeds-refresh";
          runtimeInputs = [ pkgs.curl ];
          text = ''
            token="$(< ${escapeShellArg cfg.tokenFile})"
            status="$(printf 'header = "X-Auth-Token: %s"\n' "$token" \
              | curl --config - --silent --show-error --output /dev/null --write-out '%{http_code}' \
                --max-time 30 --request PUT ${escapeShellArg "${removeSuffix "/" cfg.url}/v1/feeds/refresh"})"
            if [ "$status" = 204 ]; then
              echo "Miniflux is refreshing all feeds, reload Newsboat in a few seconds."
            else
              echo "Miniflux answered HTTP $status" >&2
              exit 1
            fi
          '';
        })
      ];

      # cache.db and the search/command histories (XDG layout, the config is in
      # ~/.config/newsboat): no full resync after every reboot
      home.mine.persistence.cache.directories = [ ".local/share/newsboat" ];

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
            # feeds no longer in Miniflux leave their entries in the local cache; the cache is
            # disposable (Miniflux is the source of truth), so drop them on quit
            "cleanup-on-quit yes"

            # colors as terminal colors: the terminal is themed by stylix (base16), so
            # Newsboat follows the theme (stylix has no Newsboat target)
            "color background default default"
            "color listnormal default default"
            "color listfocus black blue bold"
            "color listnormal_unread blue default bold"
            "color listfocus_unread black blue bold"
            "color info black green bold"
            "color article default default"
            ''highlight article "^(Feed|Title|Author|Link|Date):" cyan default bold''
            ''highlight article "https?://[^ ]+" blue default underline''
          ]
          # `,u`: Miniflux fetches all feeds now, then reload. Newsboat can only run commands
          # as a browser: the macro swaps in feeds-refresh (the URL is ignored), opens the
          # selected entry with it, restores the browser and reloads.
          ++ optional (cfg.url != null && cfg.tokenFile != null)
            ''macro u set browser "feeds-refresh; sleep 5; true %u" ; open-in-browser ; set browser "${config.programs.newsboat.browser} %u" ; reload-all''
        );
        autoFetchArticles = {
          enable = cfg.autoFetch;
          onCalendar = "hourly";
        };
      };
    };
}
