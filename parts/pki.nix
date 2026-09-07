{ ... }:
{
  perSystem = { pkgs, ... }: {
    packages.pki = pkgs.callPackage ../pkgs/pki { };
  };
}
