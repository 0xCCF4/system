# Modules

This directory contains modularized NixOS settings.

## ./nixos
Contains NixOS modules shared among all hosts. Generally, can be applied to
any of my NixOS machines, be it a VM, a server, a workstation.

These modules may be useful to other peoples, hence they are exported via `flake.nixosModules`

## ./nixos/mine
Contains NixOS modules tailored to the specific setup of my machines, still
shared among them.

These modules are not exported via the flake outputs.

## ./noxa
Contains noxa modules applied to my host config.

These modules may be useful to other peoples, hence they are exported via `flake.noxaModules`

## ./noxa/mine
Contains noxa modules applied specific to my setup,
hence not exported.