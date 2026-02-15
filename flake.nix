{
  description = "NixOS configuration";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/release-25.05";

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
      # url = "/home/mx/Documents/noxa";
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

    # Timetrax
    timetrax = {
      url = "github:0xCCF4/timetrax";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ flake-parts, ... }:
    # https://flake.parts/module-arguments.html
    flake-parts.lib.mkFlake { inherit inputs; } (top@{ config, withSystem, moduleWithSystem, ... }: {
      imports = [
        ./parts
      ];
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
    });
}
