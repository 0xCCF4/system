{ pkgs
, lib
, config
, noxa
, ...
}:
with lib;
let
  cfg = config.mine.eduroam;

  # the institution's RADIUS CA (mine.eduroam.caCert, set in external/private)
  caCert = pkgs.writeText "eduroam-ca.pem" cfg.caCert;

  secretIdent = "eduroam-password";
  secretModule = "mine.eduroam";
in
{
  options.mine.eduroam = {
    enable = mkEnableOption "eduroam wifi via a declarative NetworkManager profile";

    username = mkOption {
      type = types.str;
      default = "";
      description = "eduroam username, e.g. user@example.org.";
    };

    caCert = mkOption {
      type = types.nullOr types.lines;
      default = null;
      description = "PEM of the CA that signs the institution's RADIUS server certificate (public, from its eduroam installer). Set in external/private.";
    };
    anonymousIdentity = mkOption {
      type = types.str;
      default = "";
      description = "Outer EAP identity presented before authentication, e.g. anonymous@institutionID.";
    };

    domainMatch = mkOption {
      type = types.str;
      default = "";
      description = "Expected RADIUS server certificate domain, e.g. radius.example.org.";
    };
  };

  config = mkIf (cfg.enable && config.noxa.secrets.enable) {
    assertions = [
      {
        assertion = cfg.caCert != null;
        message = "mine.eduroam.caCert must be set (the RADIUS CA), without it the server is not verified.";
      }
    ];

    noxa.secrets.def = [
      {
        ident = secretIdent;
        module = secretModule;
      }
    ];

    # Secret file must contain a line: EDUROAM_PASSWORD=<password>
    networking.networkmanager.ensureProfiles = {
      environmentFiles = [
        config.age.secrets.${
        noxa.lib.secrets.computeIdentifier {
          ident = secretIdent;
          module = secretModule;
        }
        }.path
      ];

      profiles.eduroam = {
        connection = {
          id = "eduroam";
          type = "wifi";
          permissions = "";
        };
        wifi = {
          mode = "infrastructure";
          ssid = "eduroam";
        };
        wifi-security = {
          key-mgmt = "wpa-eap";
        };
        "802-1x" = {
          eap = "peap";
          phase2-auth = "mschapv2";
          identity = cfg.username;
          anonymous-identity = cfg.anonymousIdentity;
          domain-match = cfg.domainMatch;
          ca-cert = "${caCert}";
          password = "$EDUROAM_PASSWORD";
        };
        ipv4.method = "auto";
        ipv6.method = "auto";
      };
    };
  };
}
