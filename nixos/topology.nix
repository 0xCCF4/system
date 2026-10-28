{ inputs
, config
, options
, lib
, noxa
, ...
}:
with lib;
let
  inherit (config.lib.topology) mkConnection mkConnectionRev;

  hostId = config.topology.id;
  removeMask = address: head (splitString "/" address);

  # (only) the servers of a noxa WireGuard network are dialled by its other members
  wireguardServers = network: attrNames (filterAttrs
    (name: member: member.advertise.server != null)
    (noxa.wireguard.${network}.members or { }));

  # NixOS containers with their own veth pair (ve-<name> on the host, eth0 inside)
  vethContainers = filterAttrs (name: container: container.privateNetwork) config.containers;

  guestNetwork = "guests-${hostId}";
  hasGuests = vethContainers != { } || config.mine.vm.guests != { };
in
{
  imports = [ inputs.nix-topology.nixosModules.default ];

  # The guests need the topology module as well to be picked up by the
  # nixos-container and microvm extractors
  options.containers = mkOption {
    type = types.attrsOf (types.submodule {
      config.config.imports = [ inputs.nix-topology.nixosModules.default ];
    });
  };

  config = {
    topology = mkMerge [
      # WireGuard (noxa generates the interfaces, no extractor exists for them):
      # the server defines the network, the clients connect to it
      {
        networks = mapAttrs
          (network: wg: mkIf wg.kind.isServer {
            name = "WireGuard ${network}";
            cidrv4 = wg.networkAddress;
            cidrv6 = wg.networkAddress6;
          })
          config.noxa.wireguard.interfaces;

        self.interfaces = mapAttrs
          (network: wg: {
            type = "wireguard";
            virtual = true;
            addresses = map removeMask wg.deviceAddresses;
            network = mkIf wg.kind.isServer network;
            physicalConnections = optionals (!wg.kind.isServer)
              (map (server: mkConnection server network) (wireguardServers network));
          })
          config.noxa.wireguard.interfaces;
      }

      # Guests (containers, microVMs) of this host, routed by the host
      (mkIf hasGuests {
        networks.${guestNetwork} = {
          name = "Guests of ${hostId}";
          cidrv6 = mkIf (config.mine.guestUla.containers != [ ] || config.mine.guestUla.microvms != [ ])
            config.mine.guestUla.network;
        };
      })

      # Containers with privateNetwork: the extractor only knows macvlans and
      # `interfaces`, so the veth pair is added here
      {
        nodes = mkMerge (mapAttrsToList
          (name: container: {
            ${hostId}.interfaces."ve-${name}" = {
              type = "veth";
              virtual = true;
              addresses = optional (container.hostAddress6 != null) (removeMask container.hostAddress6)
                ++ optional (container.hostAddress != null) container.hostAddress;
              network = guestNetwork;
            };
            ${container.config.topology.id}.interfaces.eth0 = {
              type = "veth";
              virtual = true;
              physicalConnections = [ (mkConnectionRev hostId "ve-${name}") ];
            };
          })
          vethContainers);
      }

      # microVMs (mine.vm.guests): one routed tap each. The microvm extractor would name
      # the guest's interface after the host's tap, so the nodes are described here
      (mkIf (config.mine.vm.guests != { }) {
        extractors.microvm.enable = false;

        dependentConfigurations = mapAttrsToList
          (name: guest: config.microvm.vms.${name}.config.config.topology.definitions)
          config.mine.vm.guests;

        self.interfaces = mapAttrs'
          (name: guest: nameValuePair guest.tap {
            type = "tap";
            virtual = true;
            addresses = [ config.mine.guestUla.hostAddress ];
            network = guestNetwork;
          })
          config.mine.vm.guests;

        nodes = mapAttrs'
          (name: guest:
            let
              vm = config.microvm.vms.${name}.config.config;
              ramGB = vm.microvm.mem / 1024.0;
            in
            nameValuePair vm.topology.id {
              guestType = "microvm";
              parent = hostId;
              hardware.info = mkVMOverride "microvm, ${toString (builtins.floor ramGB)}GB RAM";
              interfaces.${config.mine.vm.guestInterface} = {
                inherit (guest) mac;
                network = guestNetwork;
                physicalConnections = [ (mkConnectionRev hostId guest.tap) ];
              };
            })
          config.mine.vm.guests;
      })
    ];
  } // optionalAttrs (options ? microvm) {
    # (microvm.vms only exists with the microvm host module)
    microvm.vms = genAttrs config.mine.microvm.names (vmName: {
      config.imports = [ inputs.nix-topology.nixosModules.default ];
    });
  };
}
