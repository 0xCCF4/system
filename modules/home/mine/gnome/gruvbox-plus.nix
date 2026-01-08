{ pkgs }:
pkgs.stdenv.mkDerivation {
  name = "gruvbox-plus";

  src = pkgs.fetchurl {
    url = https://github.com/SylEleuth/gruvbox-plus-icon-pack/releases/download/v6.2.0/gruvbox-plus-icon-pack-6.2.0.zip;
    sha256 = "sha256-D+SPhucHU4Riz0mzU1LnaEkkaQt+blJMAsA5r6fTAQ0=";
  };

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out
    ${pkgs.unzip}/bin/unzip $src -d $out/
  '';

  dontFixup = true;
}
