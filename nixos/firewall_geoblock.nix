{ config
, lib
, pkgs
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

    exemptWireguard = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Exempt the listen ports of this host's WireGuard interfaces (wg-quick,
        networking.wireguard, networkd), so roaming peers connect from anywhere; the
        services behind WireGuard are reached through it.
      '';
    };

    exemptPorts = {
      tcp = mkOption {
        type = types.listOf types.port;
        default = [ ];
        description = ''
          Destination TCP ports exempt from geo-blocking.
        '';
      };

      udp = mkOption {
        type = types.listOf types.port;
        default = [ ];
        description = ''
          Destination UDP ports exempt from geo-blocking.
        '';
      };
    };

    exemptSources = {
      ipv4 = mkOption {
        type = types.listOf types.str;
        default = [ "10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16" "169.254.0.0/16" "100.64.0.0/10" ];
        description = ''
          IPv4 sources exempt from geo-blocking, by default the local networks (in no
          country's list, e.g. the LAN behind an external interface).
        '';
      };

      ipv6 = mkOption {
        type = types.listOf types.str;
        default = [ "fe80::/10" "fc00::/7" ];
        description = "IPv6 sources exempt from geo-blocking, by default link-local and ULA.";
      };
    };

    externalInterfaces = mkOption {
      type = types.listOf types.str;
      default = config.mine.wanInterfaces;
      defaultText = literalExpression "config.mine.wanInterfaces";
      description = ''
        Interface names that carry traffic arriving from the public
        internet. Only packets entering on one of these interfaces are
        subject to geo-blocking.
      '';
    };

    zonesV4Url = mkOption {
      type = types.str;
      default = "https://www.ipdeny.com/ipblocks/data/countries/all-zones.tar.gz";
      description = "URL of the ipdeny IPv4 country zone tarball.";
    };

    zonesV6Url = mkOption {
      type = types.str;
      default = "https://www.ipdeny.com/ipv6/ipaddresses/blocks/ipv6-all-zones.tar.gz";
      description = "URL of the ipdeny IPv6 country zone tarball.";
    };

    updateInterval = mkOption {
      type = types.str;
      default = "daily";
      description = ''
        systemd calendar spec for how often the country zone lists are
        re-downloaded from ipdeny and the nftables set refreshed.
      '';
    };

    cacheDirectory = mkOption {
      type = types.str;
      default = "/var/lib/geoblock";
      description = ''
        Where downloaded country zone files are cached between updates.
        Used to (re-)populate the `geo-list4`/`geo-list6` sets immediately at boot,
        before the network is up, from the last successfully fetched data.
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

      wireguardPorts = filter isInt (
        mapAttrsToList (_: interface: interface.listenPort or null) config.networking.wg-quick.interfaces
        ++ mapAttrsToList (_: interface: interface.listenPort or null) config.networking.wireguard.interfaces
        ++ mapAttrsToList (_: netdev: netdev.wireguardConfig.ListenPort or null) config.systemd.network.netdevs
      );
      exemptUdp = unique (cfg.exemptPorts.udp ++ optionals cfg.exemptWireguard wireguardPorts);

      # `exclude` takes priority over `include`
      effectiveInclude = filter (c: !(elem c cfg.exclude)) cfg.include;

      activeCountries = if mode == "include" then effectiveInclude else cfg.exclude;

      dropRules =
        if mode == "include" then ''
          ip saddr != @geo-list4 drop
          ip6 saddr != @geo-list6 drop
        '' else ''
          ip saddr @geo-list4 drop
          ip6 saddr @geo-list6 drop
        '';

      countryCodesShell = concatStringsSep " "
        (map (c: "'" + (replaceStrings [ "'" ] [ "'\\''" ] c) + "'") activeCountries);

      fetchScript = pkgs.writeShellApplication {
        name = "geoblock-fetch";
        runtimeInputs = [ pkgs.curl pkgs.gnutar pkgs.gzip pkgs.coreutils pkgs.systemd ];
        text = ''
          WORK="$(mktemp -d -t geoblock-fetch.XXXXXXXXXX)"
          trap 'rm -rf "$WORK"' EXIT

          echo "[geoblock-fetch] downloading zone lists"
          # At boot the Persistent= timer fires right away, often before the local resolver
          # (dnscrypt-proxy, which first fetches its resolver list) answers: retry every
          # error, DNS failures included, for up to 5 minutes
          fetch() {
            curl -fsSL --retry 20 --retry-delay 15 --retry-all-errors --retry-max-time 300 \
              "$1" -o "$2"
          }
          fetch ${escapeShellArg cfg.zonesV4Url} "$WORK/v4.tar.gz"
          fetch ${escapeShellArg cfg.zonesV6Url} "$WORK/v6.tar.gz"

          mkdir -p "$WORK/v4" "$WORK/v6"
          tar -xzf "$WORK/v4.tar.gz" -C "$WORK/v4"
          tar -xzf "$WORK/v6.tar.gz" -C "$WORK/v6"

          COUNTRIES=(${countryCodesShell})
          for cc in "''${COUNTRIES[@]}"; do
            [ -s "$WORK/v4/$cc.zone" ] || { echo "[geoblock-fetch] missing/empty $cc.zone (v4)" >&2; exit 1; }
            [ -s "$WORK/v6/$cc.zone" ] || { echo "[geoblock-fetch] missing/empty $cc.zone (v6)" >&2; exit 1; }
          done

          install -d -m 0755 ${escapeShellArg cfg.cacheDirectory}
          for zone in v4 v6; do
            rm -rf "${cfg.cacheDirectory}/$zone.old"
            if [ -d "${cfg.cacheDirectory}/$zone" ]; then
              mv "${cfg.cacheDirectory}/$zone" "${cfg.cacheDirectory}/$zone.old"
            fi
            mv "$WORK/$zone" "${cfg.cacheDirectory}/$zone"
            rm -rf "${cfg.cacheDirectory}/$zone.old"
          done

          echo "[geoblock-fetch] done, refreshing the geo-list sets"
          systemctl restart geoblock-update-set.service
        '';
      };

      updateSetScript = pkgs.writeShellApplication {
        name = "geoblock-update-set";
        runtimeInputs = [ pkgs.nftables pkgs.gawk pkgs.gnused pkgs.coreutils ];
        text = ''
          V4_DIR=${escapeShellArg cfg.cacheDirectory}/v4
          V6_DIR=${escapeShellArg cfg.cacheDirectory}/v6

          if [ ! -d "$V4_DIR" ] || [ ! -d "$V6_DIR" ]; then
            echo "[geoblock-update-set] no cached zone data yet - leaving the geo-list sets untouched" >&2
            exit 0
          fi

          ELEMENTS4="$(mktemp -t geoblock-elements4.XXXXXXXXXX)"
          ELEMENTS6="$(mktemp -t geoblock-elements6.XXXXXXXXXX)"
          RULES="$(mktemp -t geoblock-rules.XXXXXXXXXX)"
          trap 'rm -f "$ELEMENTS4" "$ELEMENTS6" "$RULES"' EXIT

          COUNTRIES=(${countryCodesShell})
          for cc in "''${COUNTRIES[@]}"; do
            awk '{printf "%s,\n", $1}' "$V4_DIR/$cc.zone" >> "$ELEMENTS4"
            awk '{printf "%s,\n", $1}' "$V6_DIR/$cc.zone" >> "$ELEMENTS6"
          done
          sed -i '$ s/,$//' "$ELEMENTS4" "$ELEMENTS6"

          {
            echo "flush set inet geo-block geo-list4"
            echo "add element inet geo-block geo-list4 { $(cat "$ELEMENTS4") }"
            echo "flush set inet geo-block geo-list6"
            echo "add element inet geo-block geo-list6 { $(cat "$ELEMENTS6") }"
          } > "$RULES"

          nft -f "$RULES"
          echo "[geoblock-update-set] geo-list sets refreshed"
        '';
      };
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
          set geo-list4 {
            type ipv4_addr
            flags interval
            auto-merge
          }

          set geo-list6 {
            type ipv6_addr
            flags interval
            auto-merge
          }

          chain geo-prerouting {
            type filter hook prerouting priority filter; policy accept;

            ${if cfg.externalInterfaces == [ ] then ''
              # No external interfaces configured -- geo-blocking is a no-op.
              accept
            '' else ''
              iifname != { ${concatStringsSep ", " cfg.externalInterfaces} } accept
            ''}

            meta l4proto { icmp, icmpv6 } accept

            ${optionalString cfg.allowOutgoing ''
              # Outgoing open connections (or NAT64 replies) are OK
              ct state established,related accept
            ''}

            ${optionalString (cfg.exemptPorts.tcp != [ ]) ''
              tcp dport { ${concatStringsSep ", " (map toString cfg.exemptPorts.tcp)} } accept
            ''}
            ${optionalString (exemptUdp != [ ]) ''
              udp dport { ${concatStringsSep ", " (map toString exemptUdp)} } accept
            ''}

            ${optionalString (cfg.exemptSources.ipv4 != [ ]) ''
              ip saddr { ${concatStringsSep ", " cfg.exemptSources.ipv4} } accept
            ''}
            ${optionalString (cfg.exemptSources.ipv6 != [ ]) ''
              ip6 saddr { ${concatStringsSep ", " cfg.exemptSources.ipv6} } accept
            ''}

            # Incoming connection filtered against the geo-block lists
            ${dropRules}
          }
        '';
      };

      environment.persistence.${config.mine.persistence.cacheDirectory}.directories =
        mkIf config.mine.persistence.enable [ cfg.cacheDirectory ];

      systemd.services.geoblock-fetch = {
        description = "Download ipdeny country zone lists for geo-blocking";
        after = [ "network-online.target" "nss-lookup.target" ];
        wants = [ "network-online.target" "nss-lookup.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = getExe fetchScript;
        };
      };

      systemd.timers.geoblock-fetch = {
        description = "Timer for geoblock-fetch";
        timerConfig = {
          OnCalendar = cfg.updateInterval;
          OnBootSec = "5m";
          Persistent = true;
        };
        wantedBy = [ "timers.target" ];
      };

      systemd.services.geoblock-update-set = {
        description = "Populate the geo-block nftables set from cached zone data";
        after = [ "nftables.service" "local-fs.target" ];
        wants = [ "nftables.service" ];
        wantedBy = [ "multi-user.target" ];
        partOf = [ "nftables.service" ];
        unitConfig.ReloadPropagatedFrom = [ "nftables.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = getExe updateSetScript;
          ExecReload = getExe updateSetScript;
        };
      };
    };
}
