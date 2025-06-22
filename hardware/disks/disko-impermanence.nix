{ device ? throw "Set this to your disk device, e.g. /dev/sda"
, rootTmpfs ? false
, ...
}:
{
  disko.devices =
    let
      tmpSize = "1G";
    in
    {
      nodev =
        { }
        // (
          if rootTmpfs then
            {
              "/" = {
                fsType = "tmpfs";
                mountOptions = [ "size=${tmpSize}" ];
              };
            }
          else
            {
              "/tmp" = {
                fsType = "tmpfs";
                mountOptions = [ "size=${tmpSize}" ];
              };
            }
        );
      disk.main = {
        inherit device;
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            esp = {
              name = "ESP";
              size = "8G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountOptions = [
                  "fmask=0077"
                  "dmask=0077"
                ];
                mountpoint = "/boot";
              };
            };
            root = {
              name = "root";
              size = "100%";
              content = {
                type = "luks";
                name = "cryptoroot";
                askPassword = true;
                content = {
                  type = "lvm_pv";
                  vg = "nixroot_vg";
                };
              };
            };
          };
        };
      };
      lvm_vg = {
        nixroot_vg = {
          type = "lvm_vg";
          lvs = {
            root = {
              size = "100%FREE";
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ];

                subvolumes = {
                  "/root" =
                    { }
                    // (
                      if !rootTmpfs then
                        {
                          mountpoint = "/";
                        }
                      else
                        { }
                    );

                  "/persist" = {
                    mountOptions = [
                      "subvol=persist"
                      "noatime"
                    ];
                    mountpoint = "/persist";
                  };

                  "/nix" = {
                    mountOptions = [
                      "subvol=nix"
                      "noatime"
                    ];
                    mountpoint = "/nix";
                  };
                };
              };
            };
          };
        };
      };
    };
}
