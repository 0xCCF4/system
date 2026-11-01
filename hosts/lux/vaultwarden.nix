{ lib
, self
, config
, pkgs
, noxa
, specialArgs
, luxAddr6For
, luxPublicNetwork6
, ...
}:
with lib;
{
  config =
    let
      domain = self.lib.requireOption "mine.info.domain" config.mine.info.domain;

      hostAddress6 = luxAddr6For "fc00::/64" "vaultwarden-veth-host";

      adminTokenIdentifier = noxa.lib.secrets.computeIdentifier {
        module = "vaultwarden";
        ident = "admin-token";
        hosts = [ "lux" ];
      };
      adminTokenSecret = config.age.secrets.${adminTokenIdentifier};

      smtpPasswordIdentifier = noxa.lib.secrets.computeIdentifier {
        module = "mailserver";
        ident = "vaultwarden-password";
        hosts = [ "lux" ];
      };
      smtpPasswordSecret = config.age.secrets.${smtpPasswordIdentifier};
      caddyLocalAddress6 = config.containers.caddy.localAddress6;
    in
    {
      noxa.secrets.def = [
        {
          ident = "admin-token";
          module = "vaultwarden";
          hosts = [ "lux" ];
          generator.script = "alnum";
        }
      ];

      # systemd-nspawn's --bind(-ro)= parses its argument as a colon-separated
      # tuple, remove the colons (see hosts/lux/powerdns.nix for precedent).
      age.secrets.${adminTokenIdentifier}.name = "vaultwarden-admin-token";

      # Brute force (passwords, TOTP, admin token): fail2ban on lux, not in the container.
      # Vaultwarden logs the client's address (IP_HEADER, set by caddy), but everything
      # reaching the container comes from caddy, a ban there would never apply. Here the
      # ban drops the client on its way to caddy: an IPv6 /56 (one customer, as the rate
      # limits in firewall.nix), an IPv4 address alone (NAT64: 64:ff9b::<IPv4>/128; IPv4
      # neighbours are often unrelated, e.g. behind the same CGNAT or hoster).
      services.fail2ban.jails.vaultwarden.settings = {
        enabled = true;
        # fail2ban's bundled filter.d/vaultwarden.conf (passwords, TOTP, admin token)
        filter = "vaultwarden";
        # the container's journal, persisted on the host (nixos/container_journal.nix)
        backend = ''systemd[journalpath="/var/log/containers/vaultwarden/journal"]'';
        journalmatch = "_SYSTEMD_UNIT=vaultwarden.service";
        findtime = "10m";
        maxretry = 5;
        bantime = "1h";
        action = "vaultwarden-network";
      };
      environment.etc."fail2ban/action.d/vaultwarden-network.conf".text =
        let
          ban = verb: pkgs.writeShellScript "vaultwarden-ban-${verb}" ''
            network="$(${pkgs.python3}/bin/python3 -c '
            import ipaddress, sys
            address = ipaddress.ip_address(sys.argv[1])
            nat64 = ipaddress.ip_network("${config.mine.nat64.prefix}")
            if address.version == 4:
                address = nat64.network_address + int(address)  # as it reaches caddy
            # IPv4 (through the NAT64): the address alone, IPv6: its /56
            prefix = 128 if address in nat64 else 56
            print(ipaddress.ip_network(f"{address}/{prefix}", strict=False))
            ' "$1")"
            ${pkgs.nftables}/bin/nft ${verb} element inet vaultwarden-ban banned "{ $network }" || true
          '';
        in
        ''
          [Definition]
          actionban = ${ban "add"} <ip>
          actionunban = ${ban "delete"} <ip>
        '';
      networking.nftables.tables.vaultwarden-ban = {
        family = "inet";
        content = ''
          set banned {
            type ipv6_addr
            flags interval
          }

          chain forward {
            type filter hook forward priority filter - 2; policy accept;
            iifname { ${concatMapStringsSep ", " (i: ''"${i}"'') (config.mine.wanInterfaces ++ [ config.mine.nat64.interface ])} } ip6 daddr ${caddyLocalAddress6} ip6 saddr @banned drop
          }
        '';
      };

      mine.services.caddyProxy.routes.vaultwarden = {
        upstream = "[${config.containers.vaultwarden.localAddress6}]:8222";
        public = {
          enable = true;
          domain = "vault.${domain}";
        };
        # Gate the human-browsed web vault UI (and /admin) behind Anubis's
        # proof-of-work challenge, but exempt the endpoints native
        # apps/browser-extension/CLI clients hit directly -- they have no JS
        # engine to solve the challenge with, so gating these would break
        # every non-web client outright rather than just deter bots.
        anubis = {
          enable = true;
          bypassPaths = [ "/api/*" "/identity/*" "/notifications/hub" "/icons/*" ];
        };
      };

      containers.vaultwarden = {
        autoStart = true;
        privateNetwork = true;
        inherit hostAddress6;
        localAddress6 = luxAddr6For luxPublicNetwork6 "vaultwarden";
        ephemeral = true;
        inherit specialArgs;

        bindMounts.data = {
          hostPath = "/persist/data/vaultwarden";
          mountPoint = "/var/lib/vaultwarden";
          isReadOnly = false;
        };

        bindMounts.adminToken = {
          hostPath = adminTokenSecret.path;
          mountPoint = "/run/secrets/vaultwarden-admin-token";
          isReadOnly = true;
        };

        bindMounts.smtpPassword = {
          hostPath = smtpPasswordSecret.path;
          mountPoint = "/run/secrets/vaultwarden-smtp-password";
          isReadOnly = true;
        };

        config = { pkgs, ... }: {
          imports = [ (import ./container-common.nix { inherit (config.system) stateVersion; inherit (config.time) timeZone; inherit hostAddress6; }) ];

          networking.firewall.allowedTCPPorts = [ 8222 ];

          services.vaultwarden = {
            enable = true;
            config = {
              DOMAIN = "https://vault.${domain}";
              SIGNUPS_ALLOWED = false;
              ROCKET_ADDRESS = "::";
              ROCKET_PORT = 8222;
              ENABLE_WEBSOCKET = true;

              # Caddy sits directly in front (same private container network) and
              # sets X-Forwarded-For; vaultwarden's own "local" trust default only
              # trusts non-globally-routable peers, but lux's container network is
              # carved out of its real public /64, so the caddy container's address
              # *is* globally routable and would silently be distrusted. Pin trust
              # to caddy's exact address instead of relying on "local".
              IP_HEADER = "X-Forwarded-For";
              IP_HEADER_TRUSTED_PROXIES = caddyLocalAddress6;

              SMTP_HOST = "mail.${domain}";
              SMTP_PORT = 465;
              SMTP_SECURITY = "force_tls";
              SMTP_FROM = "info@vault.${domain}";
              SMTP_FROM_NAME = "Vaultwarden";
              SMTP_USERNAME = "info@vault.${domain}";
            };
          };

          # The agenix secrets are just the raw generated values (see
          # hosts/lux/powerdns.nix's api-key for the same pattern), so wrap them
          # into a proper `ADMIN_TOKEN=...`/`SMTP_PASSWORD=...` EnvironmentFile at start. Written to
          # RuntimeDirectory (tmpfs) rather than the persistent
          # /var/lib/vaultwarden bind mount, so the plaintext token never lands
          # in the host's on-disk backup.
          #
          # This is added via the generic `systemd.services.*.serviceConfig`
          # option (merged by list-concatenation with what the vaultwarden
          # module itself sets) rather than `services.vaultwarden.environmentFile`,
          # because that typed option requires a real path and rejects the "-"
          # prefix. The "-" is required: systemd assembles a unit's environment
          # (all EnvironmentFile= entries) once before running *any* Exec* phase,
          # including ExecStartPre -- so without it, every start fails before our
          # own ExecStartPre (which creates this very file) ever runs.
          systemd.services.vaultwarden.serviceConfig = {
            RuntimeDirectory = "vaultwarden";
            EnvironmentFile = [ "-/run/vaultwarden/secrets.env" ];
            ExecStartPre = mkBefore [
              "+${pkgs.writeShellScript "vaultwarden-secrets" ''
                install -m 0600 -o root -g root /dev/null /run/vaultwarden/secrets.env
                echo "ADMIN_TOKEN=$(cat /run/secrets/vaultwarden-admin-token)" > /run/vaultwarden/secrets.env
                echo "SMTP_PASSWORD=$(cat /run/secrets/vaultwarden-smtp-password)" >> /run/vaultwarden/secrets.env
              ''}"
            ];
          };
        };
      };
    };
}
