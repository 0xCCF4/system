{ lib
, config
, specialArgs
, luxAddr6For
, luxPublicNetwork6
, ...
}:
with lib;
let
  cfg = config.mine.services.jitsi;
in
{
  options.mine.services.jitsi = {
    restrictRoomCreation = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Only clients from the fleet's WireGuard networks (`wireguardNetworks`, matched on the
        client address Caddy forwards) and, with `matrixAuth.enable`, users of the own Matrix
        homeserver (Element's Jitsi widget, OpenID token in a JWT) may open a conference.
        Everyone else (link guests) can only join a conference that a host has opened. When
        false, anyone may open conferences.
      '';
    };

    wireguardNetworks = mkOption {
      type = types.listOf types.str;
      default = [ "cloud-admin" ];
      description = ''
        WireGuard networks whose clients may open conferences. The Jitsi domain is also
        served on the caddy container's ULA for them (same hostname, the fleet resolves it to
        the ULA), so their requests carry their ULA source address.
      '';
    };

    trustedPrefixes = mkOption {
      type = types.listOf types.str;
      default = map (net: config.noxa.wireguard.interfaces.${net}.networkAddress6) cfg.wireguardNetworks;
      defaultText = literalExpression "the networkAddress6 of each of `wireguardNetworks`";
      description = "Client address prefixes that may open conferences without a Matrix login.";
    };

    matrixAuth.enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Let users of the own homeserver open conferences through Element's Jitsi widget
        (`/.well-known/element/jitsi` = `{"auth":"openidtoken-jwt"}`): prosody checks the
        OpenID token in the widget's JWT against Synapse (`/_matrix/federation/v1/openid/userinfo`,
        directly, not through the public proxy) and requires a user of `mine.info.domain`.
      '';
    };
  };

  config =
    let
      hostConfig = config;

      jitsiDomain = config.mine.services.matrix.domains.jitsi;
      turnDomain = config.mine.services.matrix.domains.turn;
      jvbPort = 10000;

      hostAddress6 = luxAddr6For "fc00::/64" "jitsi-veth-host";
      containerAddr = config.containers.jitsi.localAddress6;

      restrict = cfg.restrictRoomCreation;
      matrixAuth = restrict && cfg.matrixAuth.enable;

      # the outer caddy (mine.services.caddyProxy): the only proxy whose X-Forwarded-For is
      # believed, by the inner caddy and by prosody
      outerCaddyAddresses = [ config.containers.caddy.localAddress6 ]
        ++ optional (config.mine.guestUla.addresses ? caddy) config.mine.guestUla.addresses.caddy;

      synapseUserinfoUrl =
        "http://[${config.containers.mtx-syn.localAddress6}]:8008/_matrix/federation/v1/openid/userinfo";

      luaList = xs: "{ ${concatMapStringsSep ", " (x: ''"${x}"'') xs} }";

      prosodyPlugins = pkgs': pkgs'.runCommand "jitsi-prosody-restrict-plugins" { } ''
        mkdir -p $out
        cp ${./prosody/mod_auth_jitsi_ula_or_matrix.lua} $out/mod_auth_jitsi_ula_or_matrix.lua
      '';
    in
    {
      # jitsi-meet is nixpkgs-flagged insecure because its bundled JS ships an in-call E2EE
      # feature depending on the deprecated Olm library. Set on the host because the
      # container uses the host's nixpkgs instance (nixos/container_pkgs.nix).
      nixpkgs.config.allowInsecurePredicate = pkg: builtins.elem (getName pkg) [ "jitsi-meet" ];

      assertions = [
        {
          assertion = restrict -> cfg.trustedPrefixes != [ ] || matrixAuth;
          message = "mine.services.jitsi.restrictRoomCreation: nobody could open a conference.";
        }
      ];

      mine.services.caddyProxy.routes.jitsi = {
        upstream = "[${containerAddr}]:80";
        public = {
          enable = true;
          domain = jitsiDomain;
        };
        # Element embeds calls as a widget (iframe)
        hardenHeaders.frameAncestors = "'self' https://${config.mine.services.matrix.domains.chat}";
        # Same hostname on the caddy ULA: listToAttrs keeps one vhost, bound to both
        # addresses; mine.dns.hosts / the peers' extraHosts resolve it to the ULA
        wireguardNetworks = mkIf restrict (genAttrs cfg.wireguardNetworks (_: { hostname = jitsiDomain; }));
        # Element fetches this cross-origin (from the chat domain) when a call widget is
        # created, the widget then sends an OpenID token as JWT (src/vector/jitsi/index.ts)
        extraConfig = mkIf matrixAuth ''
          respond /.well-known/element/jitsi <<ELEMENT_JITSI_WELL_KNOWN
          {"auth":"openidtoken-jwt"}
          ELEMENT_JITSI_WELL_KNOWN 200
          header /.well-known/element/jitsi Access-Control-Allow-Origin "*"
          header /.well-known/element/jitsi Content-Type "application/json"
        '';
      };

      containers.jitsi = {
        autoStart = config.mine.services.matrix.enable;
        privateNetwork = true;
        inherit hostAddress6;
        localAddress6 = luxAddr6For luxPublicNetwork6 "jitsi";
        ephemeral = true;
        inherit specialArgs;

        bindMounts.data = {
          hostPath = "/persist/data/jitsi";
          mountPoint = "/var/lib/jitsi-meet";
          isReadOnly = false;
        };

        config = { config, pkgs, ... }: {
          imports = [ (import ./container-common.nix { inherit (hostConfig.system) stateVersion; inherit (hostConfig.time) timeZone; inherit hostAddress6; }) ];

          networking.firewall.allowedTCPPorts = [ 80 ];
          networking.firewall.allowedUDPPorts = [ jvbPort ];

          services.jitsi-meet = {
            enable = true;
            hostName = jitsiDomain;

            nginx.enable = false;
            caddy.enable = true;

            # guests (guest.<domain>) can only join conferences a host has opened
            secureDomain.enable = restrict;
            secureDomain.authentication = mkIf restrict "jitsi_ula_or_matrix";

            videobridge.enable = true;

            # merged into upstream's config.js: P2P calls use our coturn instead of 8x8's
            # STUN server (meet-jit-si-turnrelay.jitsi.net), no Gravatar or other
            # third-party requests from the browsers
            config = {
              p2p.stunServers = [{ urls = "stun:${turnDomain}:3478"; }];
              disableThirdPartyRequests = true;
            };

            # Appended to config.js, which index.html pulls in with `{{ include "/config.js" }}`
            # and Caddy renders as a template: trusted (ULA) clients connect to the main
            # domain directly instead of guest.<domain>. Only the UX depends on this, prosody
            # decides on its own. Direct GETs of /config.js (Jitsi mobile/desktop apps) are
            # not rendered: the literal stays a valid, never-equal JS string there, so those
            # clients keep the guest domain.
            extraConfig = mkIf restrict ''
              if ('{{ placeholder "http.vars.jitsi_trusted_client" }}' === '1') { delete config.hosts.anonymousdomain; }
            '';
          };

          services.prosody = mkIf restrict {
            extraPluginPaths = [ "${prosodyPlugins pkgs}" ];
            # mod_http: believe X-Forwarded-For from the inner caddy (loopback) and the
            # outer caddy only
            extraConfig = ''
              trusted_proxies = ${luaList ([ "127.0.0.1" "::1" ] ++ outerCaddyAddresses)}
            '';
            virtualHosts.${jitsiDomain}.extraConfig = ''
              jitsi_trusted_prefixes = ${luaList cfg.trustedPrefixes}
              jitsi_matrix_backend = "${if matrixAuth then "userinfo" else "none"}"
            '' + optionalString matrixAuth ''
              jitsi_matrix_userinfo_url = "${synapseUserinfoUrl}"
              jitsi_matrix_server_name = "${hostConfig.mine.info.domain}"
            '';
          };

          services.caddy.globalConfig = ''
            auto_https off
          '' + optionalString restrict ''
            servers {
              trusted_proxies static ${concatMapStringsSep " " (a: "${a}/128") outerCaddyAddresses}
              trusted_proxies_strict
            }
          '';

          services.caddy.virtualHosts."http://${jitsiDomain}".extraConfig =
            optionalString restrict ''
              @jitsi_trusted_client client_ip ${concatStringsSep " " cfg.trustedPrefixes}
              vars @jitsi_trusted_client jitsi_trusted_client 1
              # the rendered index.html differs per client network
              @jitsi_page not path /libs/* /css/* /images/* /fonts/* /sounds/* /lang/* /static/*
              header @jitsi_page Cache-Control "no-store"
            ''
            + config.services.caddy.virtualHosts.${jitsiDomain}.extraConfig;

          # For dual stack support
          services.jitsi-videobridge = {
            openFirewall = false; # already opened above
            nat = {
              localAddress = containerAddr;
              publicAddress = hostConfig.mine.info.public.ipv4;
            };
          };

          systemd.services.jitsi-videobridge2 = {
            after = [ "network-addresses-eth0.service" ];
            wants = [ "network-addresses-eth0.service" ];
            path = [ pkgs.iproute2 ];
            serviceConfig.ExecStartPre = pkgs.writeShellScript "jvb-wait-for-eth0" ''
              for i in $(seq 1 30); do
                if ip -6 addr show dev eth0 | grep -q "scope global"; then
                  exit 0
                fi
                sleep 1
              done
              echo "eth0 has no global IPv6 address after 30s, starting jitsi-videobridge2 anyway"
            '';
          };
        };
      };
    };
}
