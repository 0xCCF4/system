{ pkgs
, lib
, config
, mine
, osConfig
, ...
}:
with lib;
{
  imports = [
    ./persistence.nix
  ];

  config = {
    home.mine.persistence.cache.directories = [
      ".mozilla"
      # ".cache/mozilla/firefox" TODO
    ];

    stylix.targets.firefox.profileNames = [
      "default"
    ];

    programs.firefox = {
      enable = mkDefault (mine.lib.evalMissingOption osConfig "mine.presets.isWorkstation" false);

      # Privacy about:config settings
      profiles.default = {
        id = 0;
        name = "Default MX Privacy";
        isDefault = true;

        # Install extensions from NUR
        # extensions.packages = with pkgs.nur.repos.rycee.firefox-addons; [
        #   decentraleyes
        #   ublock-origin
        #   noscript
        #   # clearurls
        #   sponsorblock
        #   darkreader
        #   h264ify
        #   # df-youtube
        #   # multi-account-containers
        #   enhancer-for-youtube
        #   # tridactyl
        #   keepassxc-browser
        # ];

        settings = {
          # General
          "browser.sessionstore.resume_session_once" = true;
          "browser.startup.homepage" = "https://nixos.org";
          "privacy.donottrackheader.enabled" = true;
          "privacy.trackingprotection.enabled" = true;
          "privacy.trackingprotection.socialtracking.enabled" = true;
          "extensions.formautofill.creditCards.enabled" = false;
          "signon.rememberSignons" = false;
          "browser.newtabpage.pinned" = "[]";
          "browser.newtabpage.blocked" =
            "{\"26UbzFJ7qT9/4DhodHKA1Q==\":1,\"4gPpjkxgZzXPVtuEoAL9Ig==\":1,\"Qm5mllFgWNfyfJYyBFM6+A==\":1,\"eV8/WsSLxHadrTL1gAxhug==\":1,\"gLv0ja2RYVgxKdp0I5qwvA==\":1,\"BRX66S9KVyZQ1z3AIk0A7w==\":1}";
          "trailhead.firstrun.branches" = "nofirstrun-empty";
          "browser.aboutwelcome.enabled" = false;
          #"general.useragent.override" = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/78.0.3904.108 Chrome/78.0.3904.108 Safari/537.36";
          "browser.tabs.firefox-view" = false;
          "browser.disableResetPrompt" = true;
          "browser.shell.defaultBrowserCheckCount" = 1;
          "browser.uiCustomization.state" =
            ''{"placements":{"widget-overflow-fixed-list":[],"unified-extensions-area":["jid1-tsgsxbhncspbwq_jetpack-browser-action","jid1-bofifl9vbdl2zq_jetpack-browser-action"],"nav-bar":["back-button","forward-button","stop-reload-button","customizableui-special-spring1","urlbar-container","customizableui-special-spring2","save-to-pocket-button","downloads-button","fxa-toolbar-menu-button","unified-extensions-button","_73a6fe31-595d-460b-a920-fcc0f8843232_-browser-action","keepassxc-browser_keepassxc_org-browser-action","sponsorblocker_ajay_app-browser-action","addon_darkreader_org-browser-action","enhancerforyoutube_maximerf_addons_mozilla_org-browser-action","ublock0_raymondhill_net-browser-action"],"toolbar-menubar":["menubar-items"],"TabsToolbar":["firefox-view-button","tabbrowser-tabs","new-tab-button","alltabs-button"],"PersonalToolbar":["personal-bookmarks"]},"seen":["developer-button","addon_darkreader_org-browser-action","jid1-bofifl9vbdl2zq_jetpack-browser-action","enhancerforyoutube_maximerf_addons_mozilla_org-browser-action","jid1-tsgsxbhncspbwq_jetpack-browser-action","_73a6fe31-595d-460b-a920-fcc0f8843232_-browser-action","sponsorblocker_ajay_app-browser-action","ublock0_raymondhill_net-browser-action","keepassxc-browser_keepassxc_org-browser-action"],"dirtyAreaCache":["nav-bar","toolbar-menubar","TabsToolbar","PersonalToolbar","unified-extensions-area"],"currentVersion":20,"newElementCount":3}'';

          "browser.send_pings" = false;
          "browser.urlbar.speculativeConnect.enabled" = false;
          "dom.event.clipboardevents.enabled" = false;
          "media.navigator.enabled" = false;
          "network.cookie.cookieBehavior" = 1;
          "network.http.referer.XOriginPolicy" = 2;
          "network.http.referer.XOriginTrimmingPolicy" = 2;
          "beacon.enabled" = false;
          "browser.safebrowsing.downloads.remote.enabled" = false;
          "network.IDN_show_punycode" = true;
          "extensions.activeThemeID" = "firefox-compact-dark@mozilla.org"; # "default-theme@mozilla.org";
          "app.shield.optoutstudies.enabled" = false;
          "dom.security.https_only_mode_ever_enabled" = true;
          "dom.security.https_only_mode" = true;
          "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
          "browser.toolbars.bookmarks.visibility" = "newtab";
          "geo.enabled" = false;

          # Disable telemetry
          "browser.newtabpage.activity-stream.feeds.telemetry" = false;
          "browser.ping-centre.telemetry" = false;
          "browser.tabs.crashReporting.sendReport" = false;
          "devtools.onboarding.telemetry.logged" = false;
          "toolkit.telemetry.enabled" = false;
          "toolkit.telemetry.unified" = false;
          "toolkit.telemetry.server" = "";
          "toolkit.telemetry.archive.enabled" = false;
          "toolkit.telemetry.prompted" = 2;
          "toolkit.telemetry.rejected" = true;
          "toolkit.telemetry.coverage.opt-out" = true;
          "toolkit.telemetry.unifiedIsOptIn" = false;
          "toolkit.telemetry.bhrPing.enabled" = false;
          "toolkit.telemetry.firstShutdownPing.enabled" = false;
          "toolkit.telemetry.hybridContent.enabled" = false;
          "toolkit.telemetry.newProfilePing.enabled" = false;
          "toolkit.telemetry.reportingpolicy.firstRun" = false;
          "toolkit.telemetry.shutdownPingSender.enabled" = false;
          "toolkit.telemetry.updatePing.enabled" = false;
          "browser.newtabpage.activity-stream.telemetry" = false;
          "experiments.activeExperiment" = false;
          "experiments.enabled" = false;
          "experiments.supported" = false;
          "network.allow-experiments" = false;
          "datareporting.healthreport.uploadEnabled" = false;
          "privacy.sanitize.clearOnShutdown.hasMigratedToNewPrefs2" = true;

          # Disable Pocket
          "browser.newtabpage.activity-stream.feeds.discoverystreamfeed" = false;
          "browser.newtabpage.activity-stream.feeds.section.topstories" = false;
          "browser.newtabpage.activity-stream.section.highlights.includePocket" = false;
          "browser.newtabpage.activity-stream.showSponsored" = false;
          "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
          "browser.newtabpage.activity-stream.default.sites" = "";
          "browser.newtabpage.activity-stream.improvesearch.topSiteSearchShortcuts.havePinned" = "amazon";
          "extensions.pocket.enabled" = false;

          # Disable prefetching
          "network.dns.disablePrefetch" = true;
          "network.prefetch-next" = false;

          # Disable JS in PDFs
          "pdfjs.enableScripting" = false;

          # Harden SSL
          "security.ssl.require_safe_negotiation" = true;

          # Extra
          "identity.fxaccounts.enabled" = false;
          "browser.search.suggest.enabled" = false;
          "browser.urlbar.shortcuts.bookmarks" = false;
          "browser.urlbar.shortcuts.history" = false;
          "browser.urlbar.shortcuts.tabs" = false;
          "browser.urlbar.suggest.bookmark" = true;
          "browser.urlbar.suggest.engines" = false;
          "browser.urlbar.suggest.history" = true;
          "browser.urlbar.suggest.openpage" = false;
          "browser.urlbar.suggest.topsites" = false;
          "browser.uidensity" = 1;
          "media.autoplay.enabled" = false;
          "toolkit.zoomManager.zoomValues" = ".8,.90,.95,1,1.1,1.2";

          "privacy.firstparty.isolate" = false;
          "privacy.userContext.enabled" = true;
          "privacy.userContext.ui.enabled" = true;
          "privacy.userContext.newTabContainerOnLeftClick.enabled" = false;
          "network.http.sendRefererHeader" = 0;
        };
      };
    };

    home.mine.unfree.allowList = [
      "enhancer-for-youtube"
    ];
  };
}
