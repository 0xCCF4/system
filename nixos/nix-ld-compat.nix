{ config, lib, pkgs, ... }:
with lib;
{
  config = {
    programs.nix-ld.enable = mkDefault config.mine.presets.isWorkstation;

    programs.nix-ld.libraries = with pkgs; [
      # list from wiki.nixos.org
      zlib
      zstd
      stdenv.cc.cc
      curl
      openssl
      attr
      libssh
      bzip2
      libxml2
      acl
      libsodium
      util-linux
      xz
      systemd

      # My own additions
      libXcomposite
      libXtst
      libXrandr
      libXext
      libX11
      libXfixes
      libGL
      libva
      pipewire
      libxcb
      libXdamage
      libxshmfence
      libXxf86vm
      libelf

      # Required
      glib
      gtk2

      # Inspired by steam
      # https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/st/steam/package.nix#L36-L85
      networkmanager
      vulkan-loader
      libgbm
      libdrm
      libxcrypt
      coreutils
      pciutils
      zenity
      # glibc_multi.bin # Seems to cause issue in ARM

      # # Without these it silently fails
      libXinerama
      libXcursor
      libXrender
      libXScrnSaver
      libXi
      libSM
      libICE
      gnome2.GConf
      nspr
      nss
      cups
      libcap
      SDL2
      libusb1
      dbus-glib
      ffmpeg
      # Only libraries are needed from those two
      libudev0-shim

      # needed to run unity
      gtk3
      icu
      libnotify
      gsettings-desktop-schemas
      # https://github.com/NixOS/nixpkgs/issues/72282
      # https://github.com/NixOS/nixpkgs/blob/2e87260fafdd3d18aa1719246fd704b35e55b0f2/pkgs/applications/misc/joplin-desktop/default.nix#L16
      # log in /home/leo/.config/unity3d/Editor.log
      # it will segfault when opening files if you don’t do:
      # export XDG_DATA_DIRS=/nix/store/0nfsywbk0qml4faa7sk3sdfmbd85b7ra-gsettings-desktop-schemas-43.0/share/gsettings-schemas/gsettings-desktop-schemas-43.0:/nix/store/rkscn1raa3x850zq7jp9q3j5ghcf6zi2-gtk+3-3.24.35/share/gsettings-schemas/gtk+3-3.24.35/:$XDG_DATA_DIRS
      # other issue: (Unity:377230): GLib-GIO-CRITICAL **: 21:09:04.706: g_dbus_proxy_call_sync_internal: assertion 'G_IS_DBUS_PROXY (proxy)' failed

      # Verified games requirements
      libXt
      libXmu
      libogg
      libvorbis
      SDL
      SDL2_image
      glew_1_10
      libidn
      tbb

      # Other things from runtime
      flac
      freeglut
      libjpeg
      libpng
      libpng12
      libsamplerate
      libmikmod
      libtheora
      libtiff
      pixman
      speex
      SDL_image
      SDL_ttf
      SDL_mixer
      SDL2_ttf
      SDL2_mixer
      libappindicator-gtk2
      libdbusmenu-gtk2
      libindicator-gtk2
      libcaca
      libcanberra
      libgcrypt
      libvpx
      librsvg
      libXft
      libvdpau
      # ...
      # Some more libraries that I needed to run programs
      pango
      cairo
      atk
      gdk-pixbuf
      fontconfig
      freetype
      dbus
      alsa-lib
      expat
      # for blender
      libxkbcommon

      libxcrypt-legacy # For natron
      libGLU # For natron

      # Appimages need fuse, e.g. https://musescore.org/fr/download/musescore-x86_64.AppImage
      fuse
      e2fsprogs

      # intellij
      SDL
      SDL2
      SDL2_image
      SDL2_mixer
      SDL2_ttf
      SDL_image
      SDL_mixer
      SDL_ttf
      alsa-lib
      at-spi2-atk
      at-spi2-core
      atk
      bzip2
      cairo
      cups
      curlWithGnuTls
      dbus
      dbus-glib
      desktop-file-utils
      e2fsprogs
      expat
      flac
      fontconfig
      freeglut
      freetype
      fribidi
      fuse
      fuse3
      gdk-pixbuf
      glew_1_10
      glib
      gmp
      gst_all_1.gst-plugins-base
      gst_all_1.gst-plugins-ugly
      gst_all_1.gstreamer
      gtk2
      harfbuzz
      icu
      keyutils.lib
      libGL
      libGLU
      libappindicator-gtk2
      libcaca
      libcanberra
      libcap
      libclang.lib
      libdbusmenu
      libdrm
      libgcrypt
      libgpg-error
      libidn
      libjack2
      libjpeg
      libmikmod
      libogg
      libpng12
      libpulseaudio
      librsvg
      libsamplerate
      libthai
      libtheora
      libtiff
      libudev0-shim
      libusb1
      libuuid
      libvdpau
      libvorbis
      libvpx
      libxcrypt-legacy
      libxkbcommon
      libxml2
      mesa
      nspr
      nss
      openssl
      p11-kit
      pango
      pixman
      python3
      speex
      stdenv.cc.cc
      tbb
      udev
      vulkan-loader
      wayland
      libICE
      libSM
      libX11
      libXScrnSaver
      libXcomposite
      libXcursor
      libXdamage
      libXext
      libXfixes
      libXft
      libXi
      libXinerama
      libXmu
      libXrandr
      libXrender
      libXt
      libXtst
      libXxf86vm
      libpciaccess
      libxcb
      xcbutil
      xcbutilimage
      xcbutilkeysyms
      xcbutilrenderutil
      xcbutilwm
      xkeyboardconfig
      xz
      zlib

      # vivado
      ncurses5
      zlib
      libuuid
      bash
      coreutils
      zlib
      stdenv.cc.cc
      libXext
      libX11
      libXrender
      libXtst
      libXi
      libXft
      libxcb
      libxcb
      freetype
      fontconfig
      glib
      gtk2
      gtk3
      graphviz
      gcc
      unzip
      nettools

      # others
      ffmpeg.dev
      openal.out
    ];
  };
}
