{ lib
, python3Packages
, cfssl
, age
, nix
}:

python3Packages.buildPythonApplication {
  pname = "pki";
  version = "0.1.0";
  pyproject = true;

  build-system = [ python3Packages.hatchling ];
  src = lib.cleanSource ./.;

  nativeCheckInputs = [ python3Packages.pytestCheckHook ];

  makeWrapperArgs = [
    "--prefix"
    "PATH"
    ":"
    (lib.makeBinPath [ cfssl age nix ])
  ];

  meta.mainProgram = "pki";
}
