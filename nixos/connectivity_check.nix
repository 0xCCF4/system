{ config
, lib
, self
, ...
}:
with lib;
let
  cfg = config.mine.connectivityCheck;
in
{
  options.mine.connectivityCheck.host = mkOption {
    type = types.nullOr types.str;
    default =
      let domain = self.nixosConfigurations.lux.config.mine.info.domain or null;
      in if domain == null then null else "captive.${domain}";
    defaultText = literalExpression ''"captive.''${lux' mine.info.domain}"'';
    description = ''
      Host of the own connectivity/captive portal check (served by lux, plain HTTP, see
      hosts/lux/connectivity_check.nix): /success.txt answers "success\n" (Firefox, also
      read by home/firefox.nix), /generate_204 an empty 204 (NetworkManager). Null: the
      defaults of Firefox and NetworkManager.
    '';
  };

  # NetworkManager: a plain HTTP request to lux instead of a third-party server; an empty
  # `response` expects HTTP 204
  config.networking.networkmanager.settings.connectivity = mkIf (cfg.host != null && config.networking.networkmanager.enable) {
    uri = "http://${cfg.host}/generate_204";
    response = "";
    interval = 300; # seconds
  };
}
