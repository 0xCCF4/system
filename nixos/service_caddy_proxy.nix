{ lib
, config
, noxa
, self
, ...
}:
with lib;
{
  options.mine.services.caddyProxy = {
    routes = mkOption {
      default = { };
      description = "Declarative reverse-proxy routes served by the caddy container.";
      type = types.attrsOf (
        types.submodule {
          options = {
            upstream = mkOption {
              type = types.str;
              description = "Backend address (host:port) this route reverse-proxies to.";
              example = "192.168.100.31:5232";
            };

            wireguardNetworks = mkOption {
              default = { };
              description = ''
                Wireguard networks (attrs, keyed by name under `noxa.wireguard.interfaces`)
                this route is exposed on. Each network gets its own dedicated hostname
                (default `"<route name><network's dns.domain>"`) so it's always
                unambiguous which address a hostname resolves to.
              '';
              type = types.attrsOf (
                types.submodule {
                  options = {
                    enable = mkOption {
                      type = types.bool;
                      default = true;
                      description = "Whether to expose the route on this network.";
                    };
                    hostname = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                      description = ''
                        Explicit hostname for this network. Leave unset to use the
                        auto-derived hostname instead.
                      '';
                      example = "todos.example.com";
                    };
                    cert = mkOption {
                      type = types.bool;
                      default = true;
                      description = ''
                        Request a real, publicly-trusted cert for this hostname via Caddy's
                        automatic HTTP-01 ACME. When false, serves this hostname with a
                        self-signed cert from Caddy's internal CA instead.
                      '';
                    };
                  };
                }
              );
            };

            public = {
              enable = mkOption {
                type = types.bool;
                default = false;
                description = ''
                  Also serve this route on the host's public interface. The flip between a
                  public and an internal route: the vhosts are bound to the caddy container's
                  addresses, an internal route (only `wireguardNetworks`) listens on its ULA
                  alone, which the ULA guard keeps unreachable from the untrusted interfaces,
                  so a spoofed Host/SNI on the public address can't reach it.
                '';
              };
              domain = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Public domain to serve this route on. Required when public.enable is true.";
              };
              denyPaths = mkOption {
                type = types.listOf types.str;
                default = [ ];
                example = [ "/_synapse/admin/*" ];
                description = ''
                  Caddy path patterns answered with 404 on the public domain (e.g. an admin API
                  that is only offered on a WireGuard network).
                '';
              };
            };

            extraConfig = mkOption {
              type = types.lines;
              default = "";
              description = ''
                Extra Caddyfile directives for every vhost of this route, before the
                route's own reverse proxy (e.g. a path-matched `reverse_proxy` to another upstream).
              '';
            };

            blockCrawlers = {
              enable = mkOption {
                type = types.bool;
                default = true;
                description = ''
                  Serve a `robots.txt` disallowing all crawlers for this route, and
                  reject requests whose `User-Agent` matches a known crawler/bot
                  (see `userAgents`) with a 403 -- regardless of whether the client
                  honors robots.txt.
                '';
              };
              userAgents = mkOption {
                type = types.listOf types.str;
                default = [
                  "GPTBot"
                  "ChatGPT-User"
                  "OAI-SearchBot"
                  "CCBot"
                  "ClaudeBot"
                  "Claude-Web" # deprecated by Anthropic, kept for safety
                  "Claude-SearchBot"
                  "Claude-User"
                  "anthropic-ai" # deprecated by Anthropic, kept for safety
                  "Bytespider"
                  "PetalBot"
                  "Amazonbot"
                  "Google-Extended"
                  "FacebookBot"
                  "meta-externalagent"
                  "Applebot-Extended"
                  "PerplexityBot"
                  "Perplexity-User"
                  "Diffbot"
                  "cohere-ai"
                  "iaskspider"
                  "YouBot"
                  "omgili"
                  "omgilibot"
                  "img2dataset"
                  "SemrushBot"
                  "AhrefsBot"
                  "MJ12bot"
                  "DotBot"
                  "YandexBot"
                ];
                description = ''
                  Case-insensitive substrings matched against the `User-Agent`
                  header; a match gets a 403 instead of being proxied upstream.
                '';
              };
            };

            securityTxt = {
              enable = mkOption {
                type = types.bool;
                default = true;
                description = ''
                  Serve a `.well-known/security.txt` (RFC 9116) directly for this
                  route.
                '';
              };
              contact = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = ''
                  Contact URI (e.g. `mailto:security@example.com`) for this route's
                  `security.txt`. Falls back to `mine.services.caddyProxy.securityTxt.contact`
                  when unset.
                '';
                example = "mailto:security@example.com";
              };
            };

            hardenHeaders = {
              enable = mkOption {
                type = types.bool;
                default = true;
                description = ''
                  Add hardening response headers for this route: `X-Content-Type-Options: nosniff`,
                  `Referrer-Policy: strict-origin-when-cross-origin`, and removal of the `Server`
                  header. Also adds `Strict-Transport-Security` (max-age=15768000, ~6 months), but
                  only on virtualHosts using a real (non self-signed) certificate -- HSTS on a
                  self-signed vhost is actively harmful, so it is never emitted there regardless of
                  this setting. And anti-framing (clickjacking): `Content-Security-Policy:
                  frame-ancestors` (see `frameAncestors`), plus `X-Frame-Options: DENY` when no
                  framing is allowed at all; both only if the upstream doesn't send its own.
                '';
              };
              frameAncestors = mkOption {
                type = types.str;
                default = "'none'";
                example = "'self' https://chat.example.com";
                description = "Who may embed this route in a frame (CSP `frame-ancestors` sources).";
              };
            };

            anubis = {
              enable = mkOption {
                type = types.bool;
                default = false;
                description = ''
                  Front this route with Anubis (a proof-of-work challenge for bots
                  and scrapers) before requests reach the real upstream. Caddy
                  reverse-proxies to a per-route Anubis instance instead of
                  `upstream` directly; Anubis itself reverse-proxies to `upstream`
                  once a client passes the challenge. Only sensible for
                  human-browser-facing routes.
                '';
              };
              difficulty = mkOption {
                type = types.nullOr types.int;
                default = null;
                description = ''
                  Override Anubis's proof-of-work difficulty for this route.
                  Leave unset (`null`) to use Anubis's built-in default.
                '';
              };
              bypassPaths = mkOption {
                type = types.listOf types.str;
                default = [ ];
                description = ''
                  Caddy path patterns (e.g. `"/api/*"`) that skip the Anubis
                  challenge and go straight to `upstream`, even when
                  `anubis.enable` is true.
                '';
                example = [ "/api/*" "/identity/*" ];
              };
              onlyPaths = mkOption {
                type = types.listOf types.str;
                default = [ ];
                description = ''
                  The inverse of `bypassPaths`: when non-empty, only requests
                  matching these Caddy path patterns (plus Anubis's own
                  `/.within.website/*` challenge endpoints and assets) go
                  through Anubis; every other request goes straight to
                  `upstream`. Mutually exclusive with `bypassPaths`.
                '';
                example = [ "/b/*" ];
              };
            };

            matrixWellKnownClient = {
              enable = mkOption {
                type = types.bool;
                default = false;
                description = ''
                  Serve `.well-known/matrix/client` for this route (with the CORS
                  header the Matrix spec requires).
                '';
              };
              content = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = ''
                  Raw JSON body served for `.well-known/matrix/client`.
                '';
                example = ''{"m.homeserver": {"base_url": "https://matrix.example.com"}}'';
              };
            };
          };
        }
      );
    };

    securityTxt = {
      contact = mkOption {
        type = types.nullOr types.str;
        default = if config.mine.info.domain != null then "mailto:security@${config.mine.info.domain}" else null;
        description = ''
          Default contact URI used for every route's `.well-known/security.txt` unless that
          route sets its own `securityTxt.contact`. Defaults to
          `mailto:security@''${mine.info.domain}` when that option is set.
        '';
        example = "mailto:security@example.com";
      };
      expires = mkOption {
        type = types.str;
        default =
          let
            # flake commit time, YYYYMMDDHHMMSS
            d = self.lastModifiedDate;
            part = start: len: substring start len d;
            monthDay = if part 4 4 == "0229" then "02-28" else "${part 4 2}-${part 6 2}";
          in
          "${toString (toInt (part 0 4) + 1)}-${monthDay}T${part 8 2}:${part 10 2}:${part 12 2}Z";
        defaultText = literalExpression "<flake commit time + 1 year>";
        description = ''
          `Expires` field of every route's `.well-known/security.txt` (RFC 9116, required).
          Defaults to one year after the commit the configuration was built from, so it
          moves forward with every deployment.
        '';
        example = "2027-01-01T00:00:00Z";
      };
    };

  };

  config =
    let
      cfg = config.mine.services.caddyProxy;
      routesPublic = filterAttrs (_: route: route.public.enable) cfg.routes;
      anubisRoutes = filterAttrs (_: route: route.anubis.enable) cfg.routes;

      wgDefaultHostname =
        routeName: network: "${routeName}${config.noxa.wireguard.interfaces.${network}.dns.domain}";

      securityTxtContact = route: if route.securityTxt.contact != null then route.securityTxt.contact else cfg.securityTxt.contact;

      routeUpstream = routeName: route:
        if route.anubis.enable
        then "unix//run/anubis/anubis-${routeName}/anubis.sock"
        else route.upstream;

      # All public-facing domain names a given route answers on (its own public
      # domain plus any per-wireguard-network names) -- used to scope
      # that route's Anubis instance's REDIRECT_DOMAINS to just the domains
      # it actually serves.
      routeDomains = routeName: route:
        (optional route.public.enable route.public.domain)
        ++ (mapAttrsToList
          (network: netCfg: if netCfg.hostname != null then netCfg.hostname else wgDefaultHostname routeName network)
          (filterAttrs (_: netCfg: netCfg.enable) route.wireguardNetworks));

      # When bypassPaths is set, matching requests skip Anubis entirely and go
      # straight to the real upstream (first match wins, same as the
      # respond-then-catch-all-reverse_proxy pattern routeExtraConfig already
      # relies on below); everything else still goes through Anubis.
      #
      # onlyPaths is the inverse: matching requests (plus Anubis's own
      # /.within.website/* challenge pages, assets and pass-challenge API,
      # without which no challenge could ever be solved) go through Anubis;
      # everything else goes straight to the real upstream.
      reverseProxyBlock = routeName: route:
        if route.anubis.enable && route.anubis.onlyPaths != [ ]
        then ''
          @anubis_only path /.within.website/* ${concatStringsSep " " route.anubis.onlyPaths}
          reverse_proxy @anubis_only ${routeUpstream routeName route}
          reverse_proxy ${route.upstream}
        ''
        else if route.anubis.enable && route.anubis.bypassPaths != [ ]
        then ''
          @anubis_bypass path ${concatStringsSep " " route.anubis.bypassPaths}
          reverse_proxy @anubis_bypass ${route.upstream}
          reverse_proxy ${routeUpstream routeName route}
        ''
        else ''
          reverse_proxy ${routeUpstream routeName route}
        '';

      routeExtraConfig =
        route: hasRealCert:
        (optionalString route.blockCrawlers.enable (''
          respond /robots.txt <<ROBOTS_TXT
          User-agent: *
          Disallow: /
          ROBOTS_TXT 200
        '' + optionalString (route.blockCrawlers.userAgents != [ ]) ''
          @blocked_crawler_ua header_regexp User-Agent "(?i)(${concatStringsSep "|" route.blockCrawlers.userAgents})"
          respond @blocked_crawler_ua 403
        ''))
        + (optionalString route.securityTxt.enable ''
          respond /.well-known/security.txt <<SECURITY_TXT
          Contact: ${securityTxtContact route}
          Expires: ${cfg.securityTxt.expires}

          SECURITY_TXT 200
        '')
        + (optionalString route.hardenHeaders.enable ''
          header {
            X-Content-Type-Options nosniff
            Referrer-Policy "strict-origin-when-cross-origin"
            -Server
            ${optionalString hasRealCert ''Strict-Transport-Security "max-age=15768000"''}
            ?Content-Security-Policy "frame-ancestors ${route.hardenHeaders.frameAncestors}"
            ${optionalString (route.hardenHeaders.frameAncestors == "'none'") "?X-Frame-Options DENY"}
          }
        '')
        + (optionalString route.matrixWellKnownClient.enable ''
          respond /.well-known/matrix/client <<MATRIX_CLIENT_WELL_KNOWN
          ${route.matrixWellKnownClient.content}
          MATRIX_CLIENT_WELL_KNOWN 200 {
            close
          }
          header /.well-known/matrix/client Access-Control-Allow-Origin "*"
          header /.well-known/matrix/client Content-Type "application/json"
        '');

      # the addresses a hostname listens on (see `public.enable`)
      bindLine = hostname: "bind ${concatMapStringsSep " " (address: "[${address}]") (
        optional (elem hostname publicDomains) caddyPublicAddress
        ++ optional (elem hostname wgHostnames) caddyUla
      )}";

      publicDenyBlock = route: optionalString (route.public.denyPaths != [ ]) ''
        @public_denied path ${concatStringsSep " " route.public.denyPaths}
        respond @public_denied 404
      '';

      selfSignedVirtualHost = hostname: routeName: route: {
        extraConfig = ''
          ${bindLine hostname}
          ${routeExtraConfig route false}
          ${route.extraConfig}
          ${reverseProxyBlock routeName route}
          tls internal {
            protocols tls1.3 tls1.3
          }
        '';
      };

      # A real, publicly-trusted cert via Caddy's own automatic HTTP-01 ACME (no explicit
      # issuer needed -- Caddy handles it by default). Requires the hostname to have a real,
      # publicly-resolvable and reachable A/AAAA record. Pin TLS to 1.3-only.
      certVirtualHost =
        hostname: routeName: route: {
          extraConfig = ''
            ${bindLine hostname}
            ${optionalString (elem hostname publicDomains) (publicDenyBlock route)}
            ${routeExtraConfig route true}
            ${route.extraConfig}
            ${reverseProxyBlock routeName route}
            tls {
              protocols tls1.3 tls1.3
            }
          '';
        };

      wgEntries = flatten (
        mapAttrsToList
          (
            routeName: route:
              mapAttrsToList
                (network: netCfg: {
                  inherit route network routeName;
                  inherit (netCfg) cert;
                  hostname = if netCfg.hostname != null then netCfg.hostname else wgDefaultHostname routeName network;
                })
                (filterAttrs (_: netCfg: netCfg.enable) route.wireguardNetworks)
          )
          cfg.routes
      );

      wgVirtualHostEntries = map
        (
          e:
          nameValuePair e.hostname (
            if e.cert then certVirtualHost e.hostname e.routeName e.route else selfSignedVirtualHost e.hostname e.routeName e.route
          )
        )
        wgEntries;

      publicEntries = mapAttrsToList
        (
          routeName: route: nameValuePair route.public.domain (certVirtualHost route.public.domain routeName route)
        )
        routesPublic;

      # The caddy container is reachable over WireGuard on its ULA (mine.guestUla),
      # both this host and the peers resolve the hostnames to it
      caddyUla = config.mine.guestUla.addresses.caddy or null;
      # ... and from the internet on its public address (directly, or via the NAT64 port forwards)
      caddyPublicAddress = config.containers.caddy.localAddress6 or null;

      publicDomains = mapAttrsToList (_: route: route.public.domain) routesPublic;
      wgHostnames = map (e: e.hostname) wgEntries;

      dnsHostsOverrides = mkMerge (map (e: { ${e.hostname} = [ caddyUla ]; }) wgEntries);

      wgPeerDnsEntries = mkMerge (map (e: { ${e.network}.dns.extraHosts.${e.hostname} = [ caddyUla ]; }) wgEntries);
    in
    mkMerge [
      {
        assertions =
          [
            {
              assertion = routesPublic != { } -> caddyPublicAddress != null;
              message = "mine.services.caddyProxy: public routes require the caddy container's localAddress6 (their bind address).";
            }
            {
              assertion = wgEntries != [ ] -> caddyUla != null;
              message = "mine.services.caddyProxy: routes exposed on WireGuard networks require the caddy container in mine.guestUla.containers.";
            }
          ]
          ++ (mapAttrsToList
            (routeName: route: {
              assertion = route.public.enable -> route.public.domain != null;
              message = "mine.services.caddyProxy.routes.${routeName}: public.domain must be set when public.enable is true.";
            })
            cfg.routes)
          ++ (mapAttrsToList
            (routeName: route: {
              assertion = route.securityTxt.enable -> securityTxtContact route != null;
              message = ''
                mine.services.caddyProxy.routes.${routeName}: securityTxt.enable is true but no
                contact is configured. Set routes.${routeName}.securityTxt.contact, the global
                mine.services.caddyProxy.securityTxt.contact, or mine.info.domain (from which the
                global default is derived).
              '';
            })
            cfg.routes)
          ++ (mapAttrsToList
            (routeName: route: {
              assertion = route.anubis.bypassPaths == [ ] || route.anubis.onlyPaths == [ ];
              message = "mine.services.caddyProxy.routes.${routeName}: anubis.bypassPaths and anubis.onlyPaths are mutually exclusive.";
            })
            cfg.routes)
          ++ (mapAttrsToList
            (routeName: route: {
              assertion = route.matrixWellKnownClient.enable -> route.matrixWellKnownClient.content != null;
              message = "mine.services.caddyProxy.routes.${routeName}: matrixWellKnownClient.content must be set when matrixWellKnownClient.enable is true.";
            })
            cfg.routes);

        mine.dns.hosts = dnsHostsOverrides;
        noxa.wireguard.interfaces = wgPeerDnsEntries;
      }
      # Only touch the caddy container's own config on the host that actually
      # declares routes (lux). Every host imports this module, and cfg.routes
      # is a plain attrsOf option -- merely *referencing* a nested attrsOf-
      # submodule path like containers.caddy.config.users.users.caddy.<x>
      # registers "caddy" as a real users.users entry with all-default values,
      # even when the value itself is `mkIf false ...`  (attrsOf key presence is
      # structural, not value-dependent). On a host where services.caddy.enable
      # never fires, nothing else supplies isSystemUser, so that phantom entry
      # fails NixOS's "exactly one of isSystemUser/isNormalUser must be set"
      # assertion -- confirmed live on ignis, which has no caddy routes at all.
      (mkIf (cfg.routes != { }) {
        containers.caddy.config = {
          services.caddy.virtualHosts = listToAttrs (
            wgVirtualHostEntries ++ publicEntries
          );

          services.anubis.instances = mapAttrs
            (
              routeName: route: {
                settings = {
                  TARGET = "http://${route.upstream}";
                  REDIRECT_DOMAINS = concatStringsSep "," (routeDomains routeName route);
                } // optionalAttrs (route.anubis.difficulty != null) {
                  DIFFICULTY = route.anubis.difficulty;
                };
              }
            )
            anubisRoutes;

          services.anubis.defaultOptions.settings.SOCKET_MODE =
            mkIf (anubisRoutes != { }) "0660";
          # Bumped from Anubis's own default of 4; a route can still override via
          # its own `anubis.difficulty`.
          services.anubis.defaultOptions.settings.DIFFICULTY =
            mkIf (anubisRoutes != { }) 5;

          users.users.caddy.extraGroups =
            mkIf (anubisRoutes != { }) [ "anubis" ];

          # Every other site (no own `bind`) is public: one listener per address and port,
          # no wildcard listener next to the bound ones (and none answering on the ULA).
          # Conservative-but-firm defaults against slow-loris-style abuse.
          services.caddy.globalConfig = ''
            ${optionalString (caddyPublicAddress != null) "default_bind [${caddyPublicAddress}]"}
            servers {
              timeouts {
                read_header 10s
                read_body 30s
                write 30s
                idle 2m
              }
            }
          '';
        };
      })
    ];
}
