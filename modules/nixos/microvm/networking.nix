{ config, lib, noxa, mine, options, ... }:
with lib; with noxa.lib.net.types; with builtins;
let
  enumeratedNetworks = imap1 (networkIndex: name: { inherit name networkIndex; }) (attrNames config.mine.vm.networks);
in
{
  options = with types; {
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
            example = [ "vm1" "vm2" ];
          };

          address = mkOption {
            type = ipNetwork;
            description = ''
              Address of the host side of the network and its network range. The host will always be x.y.z.0. if it is part of the subnet.
            '';
            default = null;
            example = "10.33.0.0/24";
          };

          host = mkOption {
            type = bool;
            description = ''
              Whether to assign the host an IP address on this network. (This will be the .0 address of the subnet.)
              If set to false, the host will not have an IP on this network and will not be part of the subnet.
            '';
            default = true;
            example = false;
          };

          nat = mkOption {
            type = bool;
            description = ''
              Whether to enable NAT/Internet access for this network. Uses the `mine.vm.externalInterface` as upstream interface.
              This requires that the host has an IP address on this network (i.e., `host` is true).
            '';
            default = false;
            example = true;
          };

          memberAddresses = mkOption {
            type = attrsOf ip;
            description = ''
              Map of microVM name to IP address to assign to that microVM on this network.
            '';
            readOnly = true;
            example = {
              vm1 = "10.33.0.1";
              vm2 = "10.33.0.2";
            };
          };

          memberMacs = mkOption {
            type = attrsOf str;
            description = ''
              Map of microVM name to MAC address to assign to that microVM on this network.
            '';
            readOnly = true;
            example = {
              vm1 = "02:7a:01:00:00:01";
              vm2 = "02:7a:01:00:00:02";
            };
          };

          netdevRuleName = mkOption {
            type = str;
            description = ''
              Name of the netdev config rule that created the virtual switch/network.
              This rule must be processed before the memberRule.
            '';
            default = "10-microvm-${last mod._prefix}";
            example = "10-microvm-vm-net";
          };

          memberRuleName = mkOption {
            type = str;
            description = ''
              Name of the network config rule that created network interfaces for each virtual machine parts of this network.
              This rule must be processed after the netdevRule.
            '';
            default = "11-microvm-${last mod._prefix}";
            example = "11-microvm-vm-net";
          };

          vmInterface = mkOption {
            type = str;
            description = ''
              Name of the network interface inside the microVMs.
              Defaults to the same name as the host interface name.
            '';
            default = mod.config.interface;
            example = "wan";
          };

          vmLinkRenameRuleName = mkOption {
            type = str;
            description = ''
              Name of the link config rule created for this network's member interfaces inside the microVMs.
              Defaults to "10-wan-<interface>".
            '';
            default = "10-wan";
            example = "10-wan";
          };
        };

        config =
          let
            enumeratedMembers = imap1 (memberIndex: name: { inherit name memberIndex; }) mod.config.members;
            networkIndex = (head (filter (entry: entry.name == last mod._prefix) enumeratedNetworks)).networkIndex;
          in
          {
            memberAddresses = mkMerge (map
              (entry: {
                "${entry.name}" = noxa.lib.net.assignAddress mod.config.address entry.memberIndex;
              })
              enumeratedMembers);

            memberMacs = mkMerge (map
              (entry: {
                "${entry.name}" =
                  let
                    spaceZero = x: if x < 16 then "0${toHexString x}" else toHexString x;
                    mac = "02:7a:${spaceZero networkIndex}:00:00:${spaceZero entry.memberIndex}";
                  in
                  trace "Debug: Assigning MAC address ${mac} to microVM ${entry.name} on network ${mod.config.interface}" mac;
              })
              enumeratedMembers);
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
                # check max length of interface names
                {
                  assertion = stringLength network.interface <= 15;
                  message = "${bold+fgYellow}MicroVM network configuration error: The interface name ${fgCyan+network.interface+fgYellow} is too long (max 15 characters due to Linux limitations).${reset}";
                }
                {
                  assertion = stringLength network.vmInterface <= 15;
                  message = "${bold+fgYellow}MicroVM network configuration error: The VM interface name ${fgCyan+network.vmInterface+fgYellow} is too long (max 15 characters due to Linux limitations).${reset}";
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
                    mac = network.memberMacs.${member.name};
                  }];

                  systemd.network.links."${network.vmLinkRenameRuleName}" = {
                    matchConfig.PermanentMACAddress = network.memberMacs.${member.name};
                    linkConfig.Name = network.interface;
                  };

                  networking.interfaces."${network.interface}" = {
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
                    address = (noxa.lib.net.decompose network.address).networkNoMask;
                    interface = network.interface;
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
