{ config, lib, noxa, mine, options, ... }:
with lib; with noxa.lib.net.types; with builtins;
{
  # config =
  #   let
  #     microvm = mine.lib.evalMissingOption config "microvm" { vms = { }; };
  #   in
  #   mkIf ((options.microvm or null) != null)
  #     (
  #       {
  #         microvm.stateDir = "/var/lib/microvms";
  #       } else
  #     { })
  # );
}
