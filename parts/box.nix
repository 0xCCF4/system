{ ... }:
{
  perSystem = { pkgs, ... }: {
    packages.box = pkgs.callPackage ../pkgs/box { };
  };
}
