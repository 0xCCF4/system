{ inputs
, lib
, self
, config
, ...
}:
with lib;
{
  ezConfigs.root = ./..;
  ezConfigs.nixos.configurationsDirectory = "${toString config.ezConfigs.root}/hosts";
  ezConfigs.nixos.modulesDirectory = "${toString config.ezConfigs.root}/nixos";

  # `self` and `noxa` are added by noxa itself
  ezConfigs.nixos.specialArgs = {
    # All these inputs will be available for all hosts, if they import them
    inherit inputs;

    inherit (inputs) nixos-hardware;
    inherit (inputs) disko;
    inherit (inputs) nixos-generators;
    inherit (inputs) impermanence;
    inherit (inputs) lanzaboote;
    inherit (inputs) agenix;
    inherit (inputs) agenix-rekey;
    inherit (inputs) microvm;
    inherit (inputs) dns;
    inherit (inputs) home-manager;
    inherit (inputs) stylix;
    inherit (inputs) nixpkgs-stable;
    inherit (inputs) adblock;
    inherit (inputs) mailserver;
    inherit (inputs) timetrax;
    inherit (inputs) frostx;
    inherit (inputs) vota;
    inherit (inputs) zrb;
    inherit (inputs.self) users;
  };

  # Agenix rekey module configuration
  flake.agenix-rekey = inputs.agenix-rekey.configure {
    userFlake = self;
    nixosConfigurations = filterAttrs (name: value: name != "iso") self.nixosConfigurations;
  };
}
