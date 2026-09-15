{ ... }:
{
  perSystem = { pkgs, ... }: {
    packages.autoclaude = pkgs.callPackage ../pkgs/autoclaude { };
  };
}
