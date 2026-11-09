{ config
, pkgs
, lib
, mineSelf
, osConfig
, ...
}:
with lib;
with builtins;
{
  imports = [
    ./traits.nix
  ];

  config = {
    programs.zed-editor = {
      enable = mkDefault true;

      installRemoteServer = true;

      extensions = [
        "docker-compose"
        "dockerfile"
        "html"
        "java"
        "lua"
        "make"
        "scala"
        "svelte"
        "toml"
      ];
      extraPackages = with pkgs; [
        clang-tools # clangd (C, C++)
        jdk # jdtls, which the java extension downloads, needs a JDK
        lua-language-server
        metals # Scala
      ];
    };
  };
}
