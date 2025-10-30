{ config, lib, noxa, mine, options, ... }:
with lib; with noxa.lib.net.types; with builtins;
{
  options = with types; {
    mine.vm.externalInterface = mkOption {
      type = str;
      description = ''
        Name of the external network interface on the host to use for NAT/Internet access for microVM networks.
      '';
    };
    mine.vm.networks = mkOption {
      default = { };
      description = ''
        List of network interfaces to attach to the microVMs.
      '';
      type = attrsOf (submodule (mod: {
        options = {
          interface = mkOption {
            type = str;
            description = ''
              Network interface name seen from the host.
              Uses the network name by default.
              Each member will create an interface with the <name>number pattern.
            '';
            default = last mod._prefix;
            example = "vm-net";
          };

          members = mkOption {
            type = listOf str;
            description = ''
              List of microVM names to attach this network to.
            '';
            default = [ ];
          };

          address = mkOption {
            type = ipNetwork;
            description = ''
              Address of the host side of the network and its network range. The host will always be .0.0.0. if it is part of the subnet.
            '';
            default = null;
          };

          host = mkOption {
            type = bool;
            description = ''
              Whether to assign the host an IP address on this network. (This will be the .0 address of the subnet.)
            '';
            default = true;
          };

          nat = mkOption {
            type = bool;
            description = ''
              Whether to enable NAT/Internet access for this network. Uses the `mine.vm.externalInterface` as upstream interface.
            '';
            default = false;
          };

          memberAddresses = mkOption {
            type = attrsOf ip;
            description = ''
              Map of microVM name to IP address to assign to that microVM on this network.
            '';
            readOnly = true;
          };

          netdevRuleName = mkOption {
            type = str;
            description = ''
              Name of the netdev config rule created for this network's bridge.
              Defaults to "10-microvm-<network name>".
            '';
            default = "10-microvm-${last mod._prefix}";
          };

          memberRuleName = mkOption {
            type = str;
            description = ''
              Name of the network config rule created for this network's member interfaces.
              Defaults to "11-microvm-<network name>".
            '';
            default = "11-microvm-${last mod._prefix}";
          };
        };

        config = {
          memberAddresses = mkMerge (imap1
            (index: vm: {
              "${vm}" = noxa.lib.net.assignAddress mod.config.address index;
            })
            mod.config.members);
        };
      }));
    };
  };

  config =
    let
      cfg = config.mine.vm;
      microvm = mine.lib.evalMissingOption config "microvm" { vms = { }; };
    in
    mkIf ((options.microvm or null) != null) (
      {
        assertions = with noxa.lib.ansi; mkMerge

          ((mapAttrsToList
            (name: network:
              [
                # member not part of microvm declaration
                {
                  assertion = all (vmName: hasAttr vmName microvm.vms) (network.members);
                  message = "${bold+fgYellow}MicroVM network configuration error: ${italic}mine.vm.'${fgCyan+name+fgYellow}'.network.members${noItalic} references unknown VM(s): ${fgRed}${concatStringsSep ", " (filter (vmName: !hasAttr vmName microvm.vms) network.members)}${fgYellow}. Did you declare them in ${fgGreen}microvm.vms.<name>${fgYellow}? ${fgCyan+(toJSON network.members)+reset}";
                }
                # member address name not part of members declaration
                {
                  assertion = all (vmName: elem vmName network.members) (attrNames network.memberAddresses);
                  message = "${bold+fgYellow}MicroVM network configuration error: ${italic}mine.vm.'${fgCyan+name+fgYellow}'.network.memberAddresses${noItalic} references unknown VM(s): ${fgRed}${concatStringsSep ", " (filter (vmName: !hasAttr vmName microvm.vms) network.memberAddresses)}${fgYellow}. Did you declare them in ${fgGreen}mine.vm.network.<name>.members${fgYellow}?${reset}";
                }
                # member address not part of subnet
                {
                  assertion = all (address: noxa.lib.net.laysWithinSubnet address network.address) (attrValues network.memberAddresses);
                  message = "${bold+fgYellow}MicroVM network configuration error: ${italic}mine.vm.'${fgCyan+name+fgYellow}'.network.memberAddresses${noItalic} references unknown VM(s): ${fgRed}${concatStringsSep ", " (filter (vmName: !hasAttr vmName microvm.vms) network.memberAddresses)}${fgYellow}. Did you declare them in ${fgGreen}microvm.vms.<name>${fgYellow}?${reset}";
                }
                # rule name check
                {
                  assertion = network.netdevRuleName != network.memberRuleName;
                  message = "${bold+fgYellow}MicroVM network configuration error: The netdev rule name and member rule name for network ${fgCyan+network.netdevRuleName+fgYellow} are identical. They must be different.${reset}";
                }

                {
                  assertion = length network.members < 255;
                  message = "You reached the artificial limit of 255 members per network. This limitations is due to the lack of MAC parsing. Feel free to open a pull request.";
                }
              ]
            )
            cfg.networks)
          ++
          [
            [
              {
                assertion = length (attrNames cfg.networks) < 255;
                message = "You reached the artificial limit of 255 networks. This limitations is due to the lack of MAC parsing. Feel free to open a pull request.";
              }
            ]
          ]
          )
        ;

        systemd.network = {
          enable = true;

          netdevs = mkMerge (
            (map
              (network: {
                "${network.netdevRuleName}" = {
                  netdevConfig = {
                    Kind = "bridge";
                    Name = network.interface;
                  };
                };
              })
              (attrValues cfg.networks))
          );

          networks = mkMerge (
            (map
              (network: {
                "${network.netdevRuleName}" = {
                  matchConfig.Name = "${network.interface}";
                  addresses = [{
                    addressConfig.Address = network.address;
                  }];
                };
                "${network.memberRuleName}" = {
                  matchConfig.Name = "${network.interface}-*";
                  networkConfig.Bridge = network.interface;
                };
              })
              (attrValues cfg.networks))
          );
        };

        networking.nat = mkIf (any (network: network.nat) (attrValues cfg.networks)) {
          enable = true;
          externalInterface = cfg.externalInterface;
          internalInterfaces = map (network: network.interface) (filter (network: network.nat) (attrValues cfg.networks));
        };


      } // (if ((options.microvm or null) != null) then {
        microvm.vms = mkMerge (map
          (
            entry:
            let
              network = entry.value.network;
            in
            mkMerge (map
              (member: {
                "${member.name}".config = {
                  microvm.interfaces = [{
                    type = "tap";
                    id = "${network.interface}-${toString member.memberIndex}";
                    mac =
                      let
                        spaceZero = x: if x < 16 then "0${toHexString x}" else toHexString x;
                        mac = "02:7a:${spaceZero entry.index}:00:00:${spaceZero member.memberIndex}";
                      in
                      trace "Debug: Assigning MAC address ${mac} to microVM ${member.name} on network ${network.interface}" mac;
                  }];

                  networking.interfaces."enp0s3" = {
                    ipv4.addresses =
                      let
                        address = noxa.lib.net.decompose network.memberAddresses.${member.name};
                      in
                      [{
                        address = address.addressNoMask;
                        prefixLength = address.mask;
                      }];
                  };

                  networking.defaultGateway = {
                    address = (noxa.lib.net.decompose network.address).deviceNoMask;
                    interface = "enp0s3";
                  };
                };
              })
              entry.value.membersEnumerated)
          )
          (mine.lib.enumerateAttrs
            (mapAttrs
              (name: value: {
                membersEnumerated = imap1 (memberIndex: name: { inherit name memberIndex; }) value.members;
                network = value;
              })
              cfg.networks)));
      } else { })
    );
}
