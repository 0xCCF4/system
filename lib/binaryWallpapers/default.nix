{ pkgs
, lib
, ...
}:
with lib;
let
  mkWallpaper = { name, src_image, src_data, primaryColor, secondaryColor, description }:
    let
      baseName = builtins.baseNameOf src_image;
      outputName = "${baseName}";

      pkg = pkgs.stdenv.mkDerivation {
        inherit name;

        dontUnpack = true;

        installPhase = ''
          mkdir -p $out
          ${pkgs.binaryWallpapers}/bin/binary-wallpapers --image ${src_image} --data ${src_data} --primary-color ${primaryColor} --secondary-color ${secondaryColor} --output $out/${outputName}
        '';

        passthru = {
          output = "${pkg}/${outputName}";
        };

        meta = with lib; {
          inherit description;
          homepage = "https://github.com/0xCCF4/system";
          license = licenses.free;
          platforms = platforms.all;
        };
      };
    in
    pkg;
in
mkWallpaper
