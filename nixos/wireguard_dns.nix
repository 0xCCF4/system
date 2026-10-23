{ lib
, config
, noxaConfig
, noxa
, ...
}:
with lib;
{
  imports = [
    ./dns.nix
  ];

  options = with types; {
    mine.dns.wireguard.enable = mkOption {
      type = bool;
      default = true;
      description = "Enable automatic dns name settings for managed wireguard networks.";
    };
    mine.dns.wireguard.domain = mkOption {
      type = str;
      default = ".wg";
      description = "The top-level domain to use for dns entries on default.";
    };

    noxa.wireguard.interfaces = mkOption {
      type = lazyAttrsOf (submodule {
        options = {
          dns.enable = mkOption {
            type = bool;
            default = true;
            description = "Add a dns entry for this host.";
          };
          dns.domain = mkOption {
            type = str;
            default = config.mine.dns.wireguard.domain;
            description = "The top-level domain to use for dns entries for this interface.";
          };
          dns.extraNames = mkOption {
            type = listOf str;
            default = [ ];
            example = [ "mail.example.com" ];
            description = ''
              Additional hostnames the peers on this network resolve to this
              host's address on it, e.g. to reach a public service name over
              the tunnel only.
            '';
          };
        };
      });
    };
  };

  config =
    let
      peerAddresses = mapAttrs
        (
          network: data:
            listToAttrs (
              map
                (
                  peer:
                  nameValuePair peer.target (
                    map (address: (noxa.lib.net.decompose address).addressNoMask)
                      noxaConfig.nodes."${peer.target}".configuration.noxa.wireguard.interfaces."${
                  network
                }".deviceAddresses
                  )
                )
                data.peers
            )
        )
        config.noxa.wireguard.routes;

      dnsEntries = flatten (
        mapAttrsToList
          (
            networkName: peers:
              let
                networkConfig = config.noxa.wireguard.interfaces.${networkName};
              in
              mapAttrsToList
                (peer: addresses: {
                  "${peer}${networkConfig.dns.domain}" = mkIf networkConfig.dns.enable addresses;
                } // genAttrs
                  noxaConfig.nodes.${peer}.configuration.noxa.wireguard.interfaces.${networkName}.dns.extraNames
                  (_: addresses))
                peers
          )
          peerAddresses
      );
    in
    mkIf config.mine.dns.wireguard.enable {
      mine.dns.hosts = mkMerge dnsEntries;
    };
}
