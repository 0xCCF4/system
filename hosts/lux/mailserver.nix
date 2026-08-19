{ lib
, config
, luxAddr6For
, luxPublicNetwork6
, mailserver
, specialArgs
, ...
}:
with lib;
{
  config.containers.mailserver =
    let
      mailserverConfig = config.containers.mailserver.config;
      hostConfig = config;
      hostAddress6 = luxAddr6For "fc00::/64" "mailserver-veth-host";
    in
    {
      autoStart = false;
      privateNetwork = true;
      inherit hostAddress6;
      localAddress6 = luxAddr6For luxPublicNetwork6 "mailserver";
      ephemeral = true;
      bindMounts.certs = {
        hostPath = "/persist/data/mailserver/certs";
        mountPoint = mailserverConfig.security.acme.certs.${mailserverConfig.mailserver.fqdn}.directory;
        isReadOnly = false;
      };
      bindMounts.acme = {
        hostPath = "/persist/cache/acme";
        mountPoint = "/var/lib/acme";
        isReadOnly = false;
      };
      inherit specialArgs;
      config =
        { config
        , pkgs
        , lib
        , ...
        }:
        {
          imports = [
            mailserver.nixosModules.mailserver
            (import ./container-common.nix { inherit (hostConfig.system) stateVersion; inherit hostAddress6; })
          ];

          security.acme = {
            acceptTerms = true;
            defaults.email = "security@johmat.de";
            certs.${config.mailserver.fqdn} = {
              # Further setup required, check the manual:
              # https://nixos.org/manual/nixos/stable/#module-security-acme
              listenHTTP = ":80";
            };
          };

          mailserver = {
            enable = false;
            stateVersion = 3;
            fqdn = "mail.johmat.de";
            domains = [ "johmat.de" ];

            # reference an existing ACME configuration
            x509.useACMEHost = config.mailserver.fqdn;

            localDnsResolver = false;

            # A list of all login accounts. To create the password hashes, use
            # nix-shell -p mkpasswd --run 'mkpasswd -s'
            loginAccounts = {
              "postmaster@johmat.de" = {
                hashedPassword = "$y$j9T$qgo2xCuskPwkggKYEvTbY.$C/.YHb2UhhYJLF6YIfnZabGjFi3nKAFDwbHV8ts2Bm0";
                aliases = [ "@johmat.de" ];
              };
            };
          };
        };
    };
}
