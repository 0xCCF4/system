{ lib
, self
, config
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

        config = { pkgs, ... }: {
          imports = [ (import ./container-common.nix { inherit (config.system) stateVersion; inherit hostAddress6; }) ];

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
            };
          };

          # The agenix secret is just the raw generated value (see
          # hosts/lux/powerdns.nix's api-key for the same pattern), so wrap it
          # into a proper `ADMIN_TOKEN=...` EnvironmentFile at start. Written to
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
            EnvironmentFile = [ "-/run/vaultwarden/admin-token.env" ];
            ExecStartPre = mkBefore [
              "+${pkgs.writeShellScript "vaultwarden-admin-token" ''
                install -m 0600 -o root -g root /dev/null /run/vaultwarden/admin-token.env
                echo "ADMIN_TOKEN=$(cat /run/secrets/vaultwarden-admin-token)" > /run/vaultwarden/admin-token.env
              ''}"
            ];
          };

          # fail2ban runs inside this container (not on the host) so it reads
          # vaultwarden's own local journal directly -- no need to reach into an
          # ephemeral container's journal from lux itself, and bans apply to this
          # container's own netns, which is exactly where the real client IP
          # (via IP_HEADER above) is visible. Uses fail2ban's own bundled
          # filter.d/vaultwarden.conf (ships upstream, covers admin-token/TOTP/
          # password failures) instead of a custom one -- vaultwarden logs to
          # the journal here (no logpath), so backend=systemd + journalmatch
          # substitutes for the upstream jail.conf example's file-tailing setup.
          services.fail2ban = {
            enable = true;
            jails.vaultwarden.settings = {
              enabled = true;
              filter = "vaultwarden";
              backend = "systemd";
              journalmatch = "_SYSTEMD_UNIT=vaultwarden.service";
              findtime = "10m";
              maxretry = 5;
              bantime = "1h";
            };
          };
        };
      };
    };
}
