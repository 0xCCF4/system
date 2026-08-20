{ lib
, config
, noxa
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
                      example = "todos.johmat.de";
                    };
                    cert = mkOption {
                      type = types.bool;
                      default = true;
                      description = ''
                        Request a real, publicly-trusted cert for this hostname, via whichever
                        `acmeMethod` is globally configured. When false, serves this hostname
                        with a self-signed cert from Caddy's internal CA instead.
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
                description = "Also serve this route on the host's public interface.";
              };
              domain = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Public domain to serve this route on. Required when public.enable is true.";
              };
            };

            robotsTxt = {
              enable = mkOption {
                type = types.bool;
                default = true;
                description = ''
                  Serve a `robots.txt` disallowing all crawlers for this route.
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
                  this setting.
                '';
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
    };

    acmeMethod = mkOption {
      type = types.enum [ "dns01" "http01" ];
      default = "http01";
      description = ''
        Challenge method used for every real (non-self-signed) cert this caddy instance issues,
        across both public and WireGuard routes. "dns01" uses the self-hosted PowerDNS API
        (dns01.apiUrl/apiKeyEnvFile); "http01" uses Caddy's standard automatic ACME (no explicit
        `tls` directive), which requires the hostname to have a real, publicly-resolvable and
        reachable A/AAAA record.
      '';
    };

    dns01 = {
      apiUrl = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          URL of the PowerDNS REST API used for DNS-01 challenges (any wireguard network with
          `dns01 = true` or a route with `public.enable = true`). Not secret - set to the
          provider's API endpoint.
        '';
        example = "http://192.168.100.41:8081";
      };

      apiKeyEnvFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Path (inside the caddy container) to an EnvironmentFile defining `POWERDNS_API_KEY`.
          Required when any route needs a real DNS-01 certificate.
        '';
      };
    };
  };

  config =
    let
      cfg = config.mine.services.caddyProxy;
      routesPublic = filterAttrs (_: route: route.public.enable) cfg.routes;

      # This host's own address on a wireguard network, mask stripped.
      wgSelfAddress =
        network:
        (noxa.lib.net.decompose (head config.noxa.wireguard.interfaces.${network}.deviceAddresses)).addressNoMask;

      wgDefaultHostname =
        routeName: network: "${routeName}${config.noxa.wireguard.interfaces.${network}.dns.domain}";

      securityTxtContact = route: if route.securityTxt.contact != null then route.securityTxt.contact else cfg.securityTxt.contact;

      routeExtraConfig =
        route: hasRealCert:
        (optionalString route.robotsTxt.enable ''
          respond /robots.txt <<ROBOTS_TXT
          User-agent: *
          Disallow: /
          ROBOTS_TXT 200
        '')
        + (optionalString route.securityTxt.enable ''
          respond /.well-known/security.txt <<SECURITY_TXT
          Contact: ${securityTxtContact route}
          SECURITY_TXT 200
        '')
        + (optionalString route.hardenHeaders.enable ''
          header {
            X-Content-Type-Options nosniff
            Referrer-Policy "strict-origin-when-cross-origin"
            -Server
            ${optionalString hasRealCert ''Strict-Transport-Security "max-age=15768000"''}
          }
        '');

      selfSignedVirtualHost = route: {
        extraConfig = ''
          ${routeExtraConfig route false}
          reverse_proxy ${route.upstream}
          tls internal {
            protocols tls1.3 tls1.3
          }
        '';
      };

      # A real, publicly-trusted cert, via whichever `acmeMethod` is configured: DNS-01 against
      # the self-hosted PowerDNS instance, or Caddy's own automatic HTTP-01 ACME (no explicit
      # issuer needed for the latter -- Caddy handles it by default). Either way, pin TLS to
      # 1.3-only.
      certVirtualHost =
        route:
        if cfg.acmeMethod == "dns01" then {
          extraConfig = ''
            ${routeExtraConfig route true}
            reverse_proxy ${route.upstream}
            tls {
              dns powerdns ${cfg.dns01.apiUrl} {$POWERDNS_API_KEY}
              protocols tls1.3 tls1.3
            }
          '';
        } else {
          extraConfig = ''
            ${routeExtraConfig route true}
            reverse_proxy ${route.upstream}
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
                  inherit route network;
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
            if e.cert then certVirtualHost e.route else selfSignedVirtualHost e.route
          )
        )
        wgEntries;

      publicEntries = mapAttrsToList
        (
          _: route: nameValuePair route.public.domain (certVirtualHost route)
        )
        routesPublic;

      dnsHostsOverrides = mkMerge (map (e: { ${e.hostname} = [ (wgSelfAddress e.network) ]; }) wgEntries);

      needsDns01 = cfg.acmeMethod == "dns01" && ((any (e: e.cert) wgEntries) || routesPublic != { });
    in
    {
      assertions =
        (mapAttrsToList
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
        ++ [
          {
            assertion = needsDns01 -> (cfg.dns01.apiUrl != null && cfg.dns01.apiKeyEnvFile != null);
            message = "mine.services.caddyProxy: dns01.apiUrl and dns01.apiKeyEnvFile must be set when acmeMethod is \"dns01\" and any wireguard network uses `cert = true` or a route uses `public.enable`.";
          }
        ];

      containers.caddy.config.services.caddy.virtualHosts = listToAttrs (
        wgVirtualHostEntries ++ publicEntries
      );

      # Conservative-but-firm defaults against slow-loris-style abuse.
      containers.caddy.config.services.caddy.globalConfig = ''
        servers {
          timeouts {
            read_header 10s
            read_body 30s
            write 30s
            idle 2m
          }
        }
      '';

      # "-" prefix: this file is generated by the caddy service's own preStart (see
      # hosts/lux/caddy.nix), so it must be tolerated as missing on the very first
      # ExecStartPre invocation.
      containers.caddy.config.systemd.services.caddy.serviceConfig.EnvironmentFile =
        mkIf needsDns01 "-${cfg.dns01.apiKeyEnvFile}";

      mine.dns.hosts = dnsHostsOverrides;

    };
}
