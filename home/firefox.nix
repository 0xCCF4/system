{ pkgs
, lib
, config
, mineSelf
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
      ".config/mozilla/firefox"
      ".mozilla"
      # ".cache/mozilla/firefox" TODO
    ];

    stylix.targets.firefox.profileNames = [
      "default"
    ];

    programs.firefox = {
      enable = mkDefault (mineSelf.lib.evalMissingOption osConfig "mine.presets.isWorkstation" false);

      configPath = ".mozilla/firefox";

      # enforced by Firefox, not changeable in about:config
      policies.DisableTelemetry = true; # all telemetry
      policies.DisableFirefoxStudies = true; # no studies/experiments (Normandy, Nimbus)

      # Extensions installed via enterprise policy, fetched from addons.mozilla.org.
      policies.ExtensionSettings =
        let
          withMode = mode: mapAttrs (_: slug: {
            installation_mode = mode;
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/${slug}/latest.xpi";
          });
        in
        # Installed automatically, can be disabled but not removed
        withMode "normal_installed"
          {
            "{446900e4-71c2-419f-a6a7-df9c091e268b}" = "bitwarden-password-manager";
            "gdpr@cavi.au.dk" = "consent-o-matic";
            "addon@darkreader.org" = "darkreader";
            "uBlock0@raymondhill.net" = "ublock-origin";
            "{d7742d87-e61d-4b78-b8a1-b469842139fa}" = "vimium-ff";
          }
        # Not installed automatically, but allowed to be installed manually
        // withMode "allowed" {
          "keepassxc-browser@keepassxc.org" = "keepassxc-browser";
          "87677a2c52b84ad3a151a4a72f5bd3c4@jetpack" = "grammarly-1";
        };

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
          "browser.sessionstore.resume_session_once" = true; # restore the last session once (after an update restart)
          "browser.startup.homepage" = "https://nixos.org"; # start page
          "privacy.donottrackheader.enabled" = false; # no DNT header: ignored by almost all sites, only a fingerprinting bit (GPC instead)
          "privacy.globalprivacycontrol.enabled" = true; # Global Privacy Control opt-out signal (legally binding under CCPA)
          "privacy.trackingprotection.enabled" = true; # tracking protection in all windows, not only private ones
          "privacy.trackingprotection.socialtracking.enabled" = true; # also block social media trackers
          "extensions.formautofill.creditCards.enabled" = false; # no card autofill (Bitwarden instead)
          "signon.rememberSignons" = false; # no built-in password manager (Bitwarden instead)
          "browser.newtabpage.pinned" = "[]"; # no pinned new tab tiles
          # hidden default new tab tiles
          "browser.newtabpage.blocked" =
            "{\"26UbzFJ7qT9/4DhodHKA1Q==\":1,\"4gPpjkxgZzXPVtuEoAL9Ig==\":1,\"Qm5mllFgWNfyfJYyBFM6+A==\":1,\"eV8/WsSLxHadrTL1gAxhug==\":1,\"gLv0ja2RYVgxKdp0I5qwvA==\":1,\"BRX66S9KVyZQ1z3AIk0A7w==\":1}";
          "trailhead.firstrun.branches" = "nofirstrun-empty"; # no first-run onboarding
          "browser.aboutwelcome.enabled" = false; # no welcome page
          #"general.useragent.override" = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/78.0.3904.108 Chrome/78.0.3904.108 Safari/537.36";
          "browser.tabs.firefox-view" = false; # no Firefox View button
          "browser.disableResetPrompt" = true; # no 'refresh Firefox' prompt
          "browser.shell.defaultBrowserCheckCount" = 1; # default-browser check counted as done
          # toolbar layout
          "browser.uiCustomization.state" =
            ''{"placements":{"widget-overflow-fixed-list":[],"unified-extensions-area":["jid1-tsgsxbhncspbwq_jetpack-browser-action","jid1-bofifl9vbdl2zq_jetpack-browser-action"],"nav-bar":["back-button","forward-button","stop-reload-button","customizableui-special-spring1","urlbar-container","customizableui-special-spring2","save-to-pocket-button","downloads-button","fxa-toolbar-menu-button","unified-extensions-button","_73a6fe31-595d-460b-a920-fcc0f8843232_-browser-action","keepassxc-browser_keepassxc_org-browser-action","sponsorblocker_ajay_app-browser-action","addon_darkreader_org-browser-action","enhancerforyoutube_maximerf_addons_mozilla_org-browser-action","ublock0_raymondhill_net-browser-action"],"toolbar-menubar":["menubar-items"],"TabsToolbar":["firefox-view-button","tabbrowser-tabs","new-tab-button","alltabs-button"],"PersonalToolbar":["personal-bookmarks"]},"seen":["developer-button","addon_darkreader_org-browser-action","jid1-bofifl9vbdl2zq_jetpack-browser-action","enhancerforyoutube_maximerf_addons_mozilla_org-browser-action","jid1-tsgsxbhncspbwq_jetpack-browser-action","_73a6fe31-595d-460b-a920-fcc0f8843232_-browser-action","sponsorblocker_ajay_app-browser-action","ublock0_raymondhill_net-browser-action","keepassxc-browser_keepassxc_org-browser-action"],"dirtyAreaCache":["nav-bar","toolbar-menubar","TabsToolbar","PersonalToolbar","unified-extensions-area"],"currentVersion":20,"newElementCount":3}'';

          "browser.send_pings" = false; # no <a ping> click tracking (default already false)
          "browser.urlbar.speculativeConnect.enabled" = false; # no connections to URL bar suggestions before Enter
          "dom.event.clipboardevents.enabled" = true; # default; false broke web apps handling copy/paste themselves (image paste in Element web, editors) (explicit: a removed pref stays in prefs.js)
          "media.navigator.enabled" = false; # only the legacy mozGetUserMedia; camera/mic (getUserMedia) stays available through WebRTC
          "network.cookie.cookieBehavior" = 5; # Total Cookie Protection: third-party cookies partitioned per site (1 blocked them, which broke SSO logins)
          "network.http.referer.XOriginPolicy" = 0; # default; 2 sent no Referer between hosts and broke SSO/payment flows
          "network.http.referer.XOriginTrimmingPolicy" = 2; # cross-origin Referer only the origin (scheme+host), no path
          "beacon.enabled" = false; # no navigator.sendBeacon (analytics on page leave)
          "browser.safebrowsing.downloads.remote.enabled" = false; # no download metadata sent to Google; local Safe Browsing lists stay
          "network.IDN_show_punycode" = true; # show punycode for international domains (homograph phishing)
          "extensions.activeThemeID" = "firefox-compact-dark@mozilla.org"; # compact dark theme
          "app.shield.optoutstudies.enabled" = false; # no Shield studies
          "dom.security.https_only_mode_ever_enabled" = true; # state marker of HTTPS-only (no effect itself)
          "dom.security.https_only_mode" = true; # HTTPS-only: HTTP sites only after a click-through
          "toolkit.legacyUserProfileCustomizations.stylesheets" = true; # allow userChrome.css (stylix)
          "browser.toolbars.bookmarks.visibility" = "newtab"; # bookmarks bar only on new tabs
          "media.peerconnection.ice.default_address_only" = true; # WebRTC only reveals the default route's address, not LAN/VPN addresses (calls still work)
          "geo.enabled" = false; # no geolocation API (maps cannot locate you)

          # Disable telemetry
          "browser.newtabpage.activity-stream.feeds.telemetry" = false; # no new tab telemetry
          "browser.tabs.crashReporting.sendReport" = false; # no automatic tab crash reports
          "toolkit.telemetry.enabled" = false; # no extended telemetry (release builds ignore it)
          "toolkit.telemetry.unified" = false; # no unified telemetry
          "toolkit.telemetry.server" = ""; # no telemetry endpoint
          "toolkit.telemetry.archive.enabled" = false; # no local telemetry archive
          "toolkit.telemetry.coverage.opt-out" = true; # no telemetry coverage ping
          "toolkit.telemetry.bhrPing.enabled" = false; # no hang reports
          "toolkit.telemetry.firstShutdownPing.enabled" = false; # no first shutdown ping
          "toolkit.telemetry.newProfilePing.enabled" = false; # no new profile ping
          "toolkit.telemetry.reportingpolicy.firstRun" = false; # no telemetry first-run notice
          "toolkit.telemetry.shutdownPingSender.enabled" = false; # no shutdown ping sender
          "toolkit.telemetry.updatePing.enabled" = false; # no update ping
          "browser.newtabpage.activity-stream.telemetry" = false; # no new tab telemetry
          "datareporting.healthreport.uploadEnabled" = false; # no technical/interaction data upload (the main telemetry switch)
          "datareporting.policy.dataSubmissionEnabled" = false; # master switch for all data submission
          "datareporting.usage.uploadEnabled" = false; # no daily usage ping (separate switch)
          "app.normandy.enabled" = false; # no remote pref changes/studies by Mozilla (Normandy)
          "app.normandy.api_url" = ""; # no Normandy endpoint
          "dom.private-attribution.submission.enabled" = false; # no Privacy-Preserving Attribution (ad measurement)
          "browser.crashReports.unsubmittedCheck.autoSubmit2" = false; # no automatic submission of pending crash reports
          "breakpad.reportURL" = ""; # no crash report endpoint
          "toolkit.coverage.opt-out" = true; # no coverage ping
          "toolkit.coverage.endpoint.base" = ""; # no coverage endpoint
          "browser.discovery.enabled" = false; # no add-on recommendations from usage data
          "extensions.htmlaboutaddons.recommendations.enabled" = false; # no recommendations in about:addons
          "browser.urlbar.suggest.quicksuggest.sponsored" = false; # no sponsored Firefox Suggest results
          "browser.urlbar.suggest.quicksuggest.nonsponsored" = false; # no Firefox Suggest results (keystrokes to Mozilla)
          "privacy.sanitize.clearOnShutdown.hasMigratedToNewPrefs2" = true; # migration marker, no effect

          # Disable Pocket
          "browser.newtabpage.activity-stream.feeds.discoverystreamfeed" = false; # no recommended stories
          "browser.newtabpage.activity-stream.feeds.section.topstories" = false; # no top stories
          "browser.newtabpage.activity-stream.showSponsored" = false; # no sponsored stories
          "browser.newtabpage.activity-stream.showSponsoredTopSites" = false; # no sponsored shortcuts
          "browser.newtabpage.activity-stream.default.sites" = ""; # no default shortcuts
          "browser.newtabpage.activity-stream.improvesearch.topSiteSearchShortcuts.havePinned" = "amazon"; # keeps the Amazon search shortcut from being pinned

          # Disable prefetching
          "network.trr.mode" = 5; # no DNS over HTTPS: the system resolver (local dnscrypt-proxy, encrypted) also resolves the .vlan names
          "network.dns.disablePrefetch" = true; # no DNS lookups for links on the page
          "network.prefetch-next" = false; # no prefetching of <link rel=next>

          # Disable JS in PDFs
          "pdfjs.enableScripting" = false; # no JavaScript in PDFs (some PDF forms lose logic)

          # Harden SSL
          "security.require_safe_negotiation" = true; # refuse TLS servers without RFC 5746 renegotiation (rare breakage, old servers)

          # Extra
          "identity.fxaccounts.enabled" = false; # no Firefox account/Sync
          "browser.search.suggest.enabled" = false; # no search suggestions (typing is not sent to the search engine)
          "browser.urlbar.shortcuts.bookmarks" = false; # no bookmarks shortcut button in the URL bar
          "browser.urlbar.shortcuts.history" = false; # no history shortcut button
          "browser.urlbar.shortcuts.tabs" = false; # no tabs shortcut button
          "browser.urlbar.suggest.bookmark" = true; # suggest bookmarks
          "browser.urlbar.suggest.engines" = false; # no search engine suggestions
          "browser.urlbar.suggest.history" = true; # suggest history
          "browser.urlbar.suggest.openpage" = false; # no open tab suggestions
          "browser.urlbar.suggest.topsites" = false; # no top sites on focus
          "browser.uidensity" = 1; # compact UI
          "media.autoplay.default" = 5; # block autoplay of audio and video, allowed per site by click
          #"toolkit.zoomManager.zoomValues" = ".8,.90,.95,1,1.1,1.2";

          "privacy.firstparty.isolate" = false; # off: superseded by Total Cookie Protection (FPI breaks more)
          "privacy.userContext.enabled" = true; # containers
          "privacy.userContext.ui.enabled" = true; # container UI
          "privacy.userContext.newTabContainerOnLeftClick.enabled" = false; # no container menu on new tab click
          "network.http.sendRefererHeader" = 2; # default; 0 sent no Referer at all, which breaks sites checking it
        } // optionalAttrs (osConfig.mine.connectivityCheck.host or null != null) (
          let check = "http://${osConfig.mine.connectivityCheck.host}/success.txt"; in {
            "captivedetect.canonicalURL" = check; # captive portal detection against lux instead of Mozilla
            "captivedetect.canonicalContent" = "success\n"; # lux' exact answer
            "network.connectivity-service.IPv4.url" = "${check}?ipv4"; # IPv4 connectivity check against lux
            "network.connectivity-service.IPv6.url" = "${check}?ipv6"; # IPv6 connectivity check against lux
            "network.connectivity-service.DNSv4.domain" = osConfig.mine.connectivityCheck.host; # has an A record
            "network.connectivity-service.DNSv6.domain" = osConfig.mine.connectivityCheck.host; # has an AAAA record
          });
      };
    };

    home.mine.unfree.allowList = [
      # "enhancer-for-youtube"
    ];
  };
}
