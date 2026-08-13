{ lib, config, noxa, ... }: with lib; {
  options.mine.services.caddyProxy = {
    routes = mkOption {
      default = { };
      description = "Declarative reverse-proxy routes served by the caddy container.";
      type = types.attrsOf (types.submodule {
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
            type = types.attrsOf (types.submodule {
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
                dns01 = mkOption {
                  type = types.bool;
                  default = true;
                  description = ''
                    Request a real cert for this hostname via DNS-01 (requires
                    `dns01.apiUrl`/`dns01.apiKeyEnvFile` to be set above). When false,
                    serves this hostname with a self-signed cert from Caddy's internal
                    CA instead.
                  '';
                };
              };
            });
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
        };
      });
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
      wgSelfAddress = network:
        (noxa.lib.net.decompose (head config.noxa.wireguard.interfaces.${network}.deviceAddresses)).addressNoMask;

      wgDefaultHostname = routeName: network:
        "${routeName}${config.noxa.wireguard.interfaces.${network}.dns.domain}";

      selfSignedVirtualHost = route: {
        extraConfig = ''
          reverse_proxy ${route.upstream}
          tls internal
        '';
      };

      # DNS-01 against the self-hosted PowerDNS instance.
      realCertVirtualHost = route: {
        extraConfig = ''
          reverse_proxy ${route.upstream}
          tls {
            dns powerdns {
              api_url ${cfg.dns01.apiUrl}
              api_key {$POWERDNS_API_KEY}
            }
          }
        '';
      };

      wgEntries = flatten (mapAttrsToList
        (routeName: route: mapAttrsToList
          (network: netCfg: {
            inherit route network;
            inherit (netCfg) dns01;
            hostname = if netCfg.hostname != null then netCfg.hostname else wgDefaultHostname routeName network;
          })
          (filterAttrs (_: netCfg: netCfg.enable) route.wireguardNetworks))
        cfg.routes);

      wgVirtualHostEntries = map
        (e: nameValuePair e.hostname (if e.dns01 then realCertVirtualHost e.route else selfSignedVirtualHost e.route))
        wgEntries;

      publicEntries = mapAttrsToList
        (_: route: nameValuePair route.public.domain (realCertVirtualHost route))
        routesPublic;

      dnsHostsOverrides = mkMerge (map
        (e: { ${e.hostname} = [ (wgSelfAddress e.network) ]; })
        wgEntries);

      needsPublicPorts = routesPublic != { };
      needsDns01 = (any (e: e.dns01) wgEntries) || routesPublic != { };
    in
    {
      assertions = (mapAttrsToList
        (routeName: route: {
          assertion = route.public.enable -> route.public.domain != null;
          message = "mine.services.caddyProxy.routes.${routeName}: public.domain must be set when public.enable is true.";
        })
        cfg.routes) ++ [
        {
          assertion = needsDns01 -> (cfg.dns01.apiUrl != null && cfg.dns01.apiKeyEnvFile != null);
          message = "mine.services.caddyProxy: dns01.apiUrl and dns01.apiKeyEnvFile must be set when any wireguard network uses `dns01 = true` or a route uses `public.enable`.";
        }
      ];

      containers.caddy.config.services.caddy.virtualHosts =
        listToAttrs (wgVirtualHostEntries ++ publicEntries);

      # "-" prefix: this file is generated by the caddy service's own preStart (see
      # hosts/lux/caddy.nix), so it must be tolerated as missing on the very first
      # ExecStartPre invocation.
      containers.caddy.config.systemd.services.caddy.serviceConfig.EnvironmentFile =
        mkIf needsDns01 "-${cfg.dns01.apiKeyEnvFile}";

      mine.dns.hosts = dnsHostsOverrides;

      containers.caddy.forwardPorts = mkIf needsPublicPorts [
        { hostPort = 80; containerPort = 80; }
        { hostPort = 443; containerPort = 443; }
        { hostPort = 443; containerPort = 443; protocol = "udp"; } # HTTP/3
      ];
    };
}
