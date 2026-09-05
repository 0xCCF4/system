{ config
, lib
, pkgs
, ipdenyZonesV4
, ipdenyZonesV6
, ...
}:
with lib;
{
  options.mine.services.geoBlock = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Geo-IP-restrict ALL inbound traffic to this host.
      '';
    };

    include = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Lowercase ISO 3166-1 alpha-2 country codes to run as an allow-list.
      '';
    };

    exclude = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Lowercase ISO 3166-1 alpha-2 country codes to run as a block-list.
      '';
    };

    allowOutgoing = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Accept packets belonging to connections this host initiated,
        regardless of the geo-block list.
        
        Note: on nftables restart connection status is reset and connections
        possible interrupted to excluded hosts.
      '';
    };
  };

  config =
    let
      cfg = config.mine.services.geoBlock;

      mode =
        if cfg.include != [ ] then "include"
        else if cfg.exclude != [ ] then "exclude"
        else null;

      conflicts = filter (c: elem c cfg.exclude) cfg.include;

      # `exclude` takes priority over `include`
      effectiveInclude = filter (c: !(elem c cfg.exclude)) cfg.include;

      activeCountries = if mode == "include" then effectiveInclude else cfg.exclude;

      # NAT64 64:ff9b::/96 needs IPv4 rewrite
      geoElements = pkgs.runCommand "geo-block.nft-elements" { } ''
        for cc in ${lib.concatStringsSep " " activeCountries}; do
          awk -F/ '{printf "64:ff9b::%s/%d,\n", $1, 96+$2}' "${ipdenyZonesV4}/$cc.zone" >> $out
          awk '{printf "%s,\n", $1}' "${ipdenyZonesV6}/$cc.zone" >> $out
        done
        sed -i '$ s/,$//' $out
      '';

      dropRule =
        if mode == "include" then "ip6 saddr != @geo-list drop"
        else "ip6 saddr @geo-list drop";
    in
    mkIf cfg.enable {
      assertions = [
        {
          assertion = mode != null;
          message = ''
            mine.services.geoBlock.enable is on but neither
            mine.services.geoBlock.include nor mine.services.geoBlock.exclude
            is set.
          '';
        }
      ];

      warnings = optional (conflicts != [ ]) ''
        mine.services.geoBlock: these countries are in both `include` and
        `exclude`: ${concatStringsSep ", " conflicts}. `exclude` takes priority.
      '';

      networking.nftables.enable = mkDefault true;

      networking.nftables.tables.geo-block = mkIf (mode != null) {
        family = "inet";
        content = ''
          set geo-list {
            type ipv6_addr
            flags interval
            auto-merge
            elements = { ${builtins.readFile geoElements} }
          }

          chain geo-prerouting {
            type filter hook prerouting priority filter; policy accept;

            meta l4proto { icmp, icmpv6 } accept

            ${optionalString cfg.allowOutgoing ''
              # Outgoing open connections (or NAT64 replies) are OK
              ct state established,related accept
            ''}

            # Incoming connection filtered against the geo-block list
            ${dropRule}
          }
        '';
      };
    };
}
