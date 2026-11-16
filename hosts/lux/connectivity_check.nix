# Connectivity and captive portal check of the laptops (nixos/connectivity_check.nix):
# Firefox and NetworkManager ask lux instead of Mozilla or a third party. Plain HTTP, so a
# captive portal can intercept it; only fixed answers, no upstream (see the assertion in
# hosts/lux/caddy.nix). Port 80 is not geo-blocked, so it also works abroad.
{ lib
, config
, ...
}:
with lib;
let
  host = config.mine.connectivityCheck.host;
in
{
  config.containers.caddy.config = mkIf (host != null) {
    mine.caddy.staticPlainHttp = [ "http://${host}" ];
    services.caddy.virtualHosts."http://${host}" = {
      logFormat = null; # no access log: it would record every laptop's address whenever it goes online
      # (no quotes or backslashes in the comments below: they break caddy's parsing of the heredoc)
      extraConfig = ''
        header Cache-Control "no-store"
        header /success.txt Content-Type "text/plain"
        # Firefox (captivedetect, network.connectivity-service): the same body as Mozilla, success and a newline
        respond /success.txt <<BODY
        success

        BODY 200
        # NetworkManager (connectivity.response empty): an empty 204
        respond /generate_204 204
        respond 404
      '';
    };
  };
}
