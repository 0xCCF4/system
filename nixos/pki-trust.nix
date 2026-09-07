{ lib, ... }:
let
  rootCertPath = ../../pki/root-ca.pem;
in
{
  config = lib.mkIf (builtins.pathExists rootCertPath) {
    security.pki.certificateFiles = [ rootCertPath ];
  };
}
