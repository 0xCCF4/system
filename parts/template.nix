{ inputs, lib, self, ... }: with lib;
{
  flake.templates.default = {
    description = "Nixos configuration template";
    path = ./..;
  };
}
