{ lib
, pkgs
, ...
}:
with lib;
{
  config = {
    mine.microvm.names = [ "paperless" ];
    microvm.vms.paperless = {
      restartIfChanged = true;
      config = {
        microvm.mem = 4096;
        imports = [ ../../hardware/microvm.nix ];

        microvm.shares = [
          {
            proto = "virtiofs";
            tag = "data";
            source = "/persist/microvms/paperless/data";
            mountPoint = "/paperless";
          }
        ];

        users.users.postgres.uid = mkForce 2000;
        users.users.postgres.isSystemUser = true;
        users.users.paperless.uid = mkForce 2001;
        users.users.paperless.isSystemUser = true;

        services.postgresql.dataDir = "/paperless/database";
        services.postgresql.package = pkgs.postgresql_16;
        services.postgresql.authentication = pkgs.lib.mkOverride 10 ''
          #type database  DBuser  auth-method
          local all       all     trust
        '';
        services.postgresql.identMap = ''
          # ArbitraryMapName systemUser DBUser
             superuser_map      root      postgres
             superuser_map      postgres  postgres
             # Let other names not login
             superuser_map      /^(.*)$   nouser
        '';
        services.paperless = {
          enable = true;
          consumptionDirIsPublic = true;
          dataDir = "/paperless/data";
          database.createLocally = true;
          configureTika = true;
          # IPv6 only, reached by the caddy microVM (see caddy.nix)
          address = "::";
          port = 8000;
          settings = {
            PAPERLESS_CONSUMER_IGNORE_PATTERN = [
              ".DS_STORE/*"
              "desktop.ini"
            ];
            PAPERLESS_OCR_LANGUAGE = "deu+eng";
            PAPERLESS_OCR_USER_ARGS = {
              optimize = 1;
              pdfa_image_compression = "lossless";
            };
            # all names served by the caddy microVM (caddy.nix): WireGuard
            # (<guest>.<host>.vlan) and an ssh tunnel to localhost:4430
            PAPERLESS_URL = "https://paperless.eternis.vlan";
            PAPERLESS_ALLOWED_HOSTS = "paperless.eternis.vlan,localhost";
            PAPERLESS_CSRF_TRUSTED_ORIGINS = "https://paperless.eternis.vlan,https://localhost:4430";
            PAPERLESS_CORS_ORIGIN_WHITELIST = "https://localhost:4430";
          };
        };

        networking.firewall.allowedTCPPorts = [ 8000 ];

        environment.systemPackages = with pkgs; [
          coreutils-full
          net-tools
          iproute2
          pciutils
          kitty
        ];
      };
    };

    # IPv6 only (ULA), own tap interface, see nixos/microvm/networking.nix. No internet,
    # only the caddy microVM reaches it.
    mine.vm.guests.paperless = { };
    mine.vm.networks.paperless.members = [ "caddy" "paperless" ];
  };
}
