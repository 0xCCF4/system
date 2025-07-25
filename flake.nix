{
  description = "Nixos system configuration";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Home Manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Nix color themes
    nix-colors.url = "github:misterio77/nix-colors";

    # Hardware specific configuration
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # Flake utils
    flake-utils.url = "github:numtide/flake-utils";

    # Partitioning tool
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Nix impermanence setup
    impermanence = {
      url = "github:nix-community/impermanence";
    };

    # Secure boot
    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secret management
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secret management
    agenix-rekey = {
      url = "github:oddlama/agenix-rekey";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # NixOS generators
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # NixOS proxmox
    proxmox-nixos = {
      url = "github:SaumonNet/proxmox-nixos";
      inputs.nixpkgs-unstable.follows = "nixpkgs";
      inputs.utils.follows = "flake-utils";
    };

    # NixOS configurable VMs
    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # NixOS dns zone file builder
    dns = {
      url = "github:kirelagin/dns.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Multi-host configuration framework
    noxa = {
      url = "github:0xCCF4/noxa";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
      inputs.agenix.follows = "agenix";
      inputs.agenix-rekey.follows = "agenix-rekey";
      inputs.flake-utils.follows = "flake-utils";
    };

    # Color themes
    stylix = {
      url = "github:danth/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self
    , nixpkgs
    , nixos-hardware
    , nixos-generators
    , disko
    , impermanence
    , lanzaboote
    , agenix
    , agenix-rekey
    , proxmox-nixos
    , microvm
    , dns
    , noxa
    , flake-utils
    , home-manager
    , stylix
    , ...
    }@inputs:
      with nixpkgs.lib; with builtins;
      let
        modules = import ./modules inputs;
        minelib = import ./lib inputs;
        minePkgs = import ./pkgs inputs;
        shells = import ./shells inputs;

        hosts = noxa.lib.nixDirectoryToAttr' ./hosts;

        noxaConfiguration = noxa.lib.noxa-instantiate {
          modules = [
            ./modules/noxa/mine
            ({ lib, ... }: {
              # overlay own packages
              defaults.configuration.imports = [
                modules.nixosModules.default
                ./modules/nixos/mine
                (
                  { pkgs, lib, ... }: {
                    nixpkgs.overlays = [ (final: prev: prev // lib.attrsets.mapAttrs (name: pkg: pkgs.callPackage pkg { }) minePkgs) ];
                  }
                )
              ];
              defaults.specialArgs = {
                inherit nixos-hardware;
                inherit disko;
                inherit nixos-generators;
                inherit impermanence;
                inherit lanzaboote;
                inherit agenix;
                inherit agenix-rekey;
                inherit proxmox-nixos;
                inherit microvm;
                inherit dns;
                inherit home-manager;
                inherit stylix;
                mine = {
                  lib = minelib;
                  inherit (self) noxaModules;
                  inherit (self) nixosModules;
                  inherit (self) homeModules;
                };
              };

              nodes = attrsets.mapAttrs
                (name: path: {
                  configuration = {
                    imports = [ path ];
                  };
                })
                hosts;

              nodeNames = attrsets.mapAttrsToList (name: path: name) hosts;
            })
            modules.noxaModules.default
          ];
        };
      in
      with nixpkgs.lib; with builtins; {
        inherit noxaConfiguration;

        lib = minelib;

        # Agenix rekey module configuration
        agenix-rekey = agenix-rekey.configure {
          userFlake = self;
          nixosConfigurations = attrsets.mapAttrs
            (name: value: {
              config = value.configuration;
            })
            self.noxaConfiguration.config.nodes;
        };

        formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixpkgs-fmt;

        nixosModules = modules.nixosModules;
        noxaModules = modules.noxaModules;
        homeModules = modules.homeModules;
      } // flake-utils.lib.eachDefaultSystem (system: {
        packages =
          let
            pkgs = import nixpkgs {
              inherit system;
            };
          in
          attrsets.mapAttrs (n: x: pkgs.callPackage x { }) minePkgs;

        devShells =
          let
            pkgs = import nixpkgs {
              inherit system;
              overlays = [

                agenix-rekey.overlays.default

                (final: prev:
                  attrsets.mapAttrs (n: x: pkgs.callPackage x { }) minePkgs
                )

              ];
            };
          in
          attrsets.mapAttrs (n: x: pkgs.callPackage x { }) shells;
      });
}
