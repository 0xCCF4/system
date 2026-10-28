{ lib
, config
, self
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
          dns.extraHosts = mkOption {
            type = attrsOf (listOf str);
            default = { };
            example = { "mail.example.com" = [ "fd12:3456:789a:1::5" ]; };
            description = ''
              Additional hostnames the peers on this network resolve to the given
              addresses, e.g. to a container behind this host.
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
                    # IPv6 only, IPv4 on the networks is reserved for traffic between peers
                    map (address: (noxa.lib.net.decompose address).addressNoMask) (filter noxa.lib.net.ip6.check
                      self.nixosConfigurations."${peer.target}".config.noxa.wireguard.interfaces."${
                  network
                }".deviceAddresses)
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
                  self.nixosConfigurations.${peer}.config.noxa.wireguard.interfaces.${networkName}.dns.extraNames
                  (_: addresses)
                // self.nixosConfigurations.${peer}.config.noxa.wireguard.interfaces.${networkName}.dns.extraHosts)
                peers
          )
          peerAddresses
      );
    in
    mkMerge [
      {
        # Per-network dns settings of the noxa topology (noxa/wireguard_dns.nix)
        noxa.wireguard.interfaces = mapAttrs
          (networkName: network: {
            dns.enable = mkDefault network.dns.enable;
            dns.domain = mkIf (network.dns.domain != null) (mkDefault network.dns.domain);
          })
          (filterAttrs (networkName: network: network.members ? ${config.networking.hostName}) noxa.wireguard);
      }
      (mkIf config.mine.dns.wireguard.enable {
        mine.dns.hosts = mkMerge dnsEntries;
      })
    ];
}
