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

    # Deploy to different hosts with magic rollback
    deploy-rs.url = "github:serokell/deploy-rs";

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
    , deploy-rs
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
    let
      modules = import ./modules inputs;
      lib = import ./lib inputs;
    in
    {
      nixosConfigurations = noxa.lib.nixos-instantiate {
        hostLocations = ./hosts;
        nixosConfigurations = self.nixosConfigurations;
        additionalArgs = {
          specialArgs = {
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
            mine.lib = lib;
          };
          modules = [
            ./modules/nixos
          ];
        };
      };

      agenix-rekey = agenix-rekey.configure {
        userFlake = self;
        nixosConfigurations = self.nixosConfigurations;
      };

      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixpkgs-fmt;

      checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;

      nixosModules = modules.nixosModules;
      noxaModules = modules.noxaModules;
      homeModules = modules.homeModules;
    } // flake-utils.lib.eachDefaultSystem (system: {
      devShells.default =
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ agenix-rekey.overlays.default ];
          };
        in
        pkgs.mkShell {
          packages = [ pkgs.agenix-rekey pkgs.rage deploy-rs.packages.${system}.deploy-rs ];
        };
    });
}
