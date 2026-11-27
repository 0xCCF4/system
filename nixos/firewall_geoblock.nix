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
      default = "weekly";
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
        runtimeInputs = [ pkgs.curl pkgs.gnutar pkgs.gzip pkgs.coreutils ];
        text = ''
          WORK="$(mktemp -d -t geoblock-fetch.XXXXXXXXXX)"
          trap 'rm -rf "$WORK"' EXIT

          echo "[geoblock-fetch] downloading zone lists"
          # At boot the Persistent= timer fires right away, often before the local resolver
          # (dnscrypt-proxy, which first fetches its resolver list) answers: retry every
          # error, DNS failures included, for up to 5 minutes.
          #
          # ipdeny resets large transfers at random offsets (curl error 56 "connection
          # reset by peer", or 92 with HTTP/2).  A plain retry restarts the tarball from
          # byte zero and usually gets reset again.  So resume with `-C -` until the
          # archive is complete and passes `gzip -t`.
          fetch() {
            url=$1
            out=$2
            tries=0
            while :; do
              # A complete archive already in place (last resume raced the end of the
              # transfer, so curl got 416) needs no further download.
              if [ -s "$out" ] && gzip -t "$out" 2>/dev/null; then
                return 0
              fi
              curl -fsSL --http1.1 -C - --connect-timeout 30 --max-time 300 \
                "$url" -o "$out" || true
              if [ -s "$out" ] && gzip -t "$out" 2>/dev/null; then
                return 0
              fi
              tries=$((tries + 1))
              if [ "$tries" -ge 20 ]; then
                echo "[geoblock-fetch] giving up on $url after $tries attempts" >&2
                return 1
              fi
              sleep 15
            done
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

          # geoblock-update-set runs with the restricted capability bounding set
          # {CAP_NET_ADMIN} only, make the cache
          # world-readable before it is moved into place.
          for zone in v4 v6; do
            chmod 0755 "$WORK/$zone"
            chmod 0644 "$WORK/$zone"/*.zone
          done

          CACHE=${escapeShellArg cfg.cacheDirectory}
          install -d -m 0755 "$CACHE"

          for zone in v4 v6; do
            rm -rf "$CACHE/$zone.old"
            if [ -d "$CACHE/$zone" ]; then
              mv "$CACHE/$zone" "$CACHE/$zone.old"
            fi
            mv "$WORK/$zone" "$CACHE/$zone"
            rm -rf "$CACHE/$zone.old"
          done

          echo "[geoblock-fetch] done"
          # Signal the geoblock-cache.path unit that the zone data changed.
          # That unit starts geoblock-update-set.service to repopulate the
          # nftables sets.  This service runs as the unprivileged `geoblock`
          # user, so it must not call systemctl itself.  A systemctl call would
          # need root.  The `.updated` marker is touched last, after the zone
          # dirs are fully swapped in, so the path unit fires with a complete
          # cache.
          touch "$CACHE/.updated"
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
          User = "geoblock";
          Group = "nogroup";
          NoNewPrivileges = true;
          ProtectSystem = true;
          ProtectHome = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectKernelTunables = true;
          ProtectControlGroups = true;
          ProtectKernelModules = true;
          ProtectKernelLogs = true;
          ProtectClock = true;
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
          LockPersonality = true;
          RemoveIPC = true;
          UMask = "0077";
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
        serviceConfig = {
          Type = "oneshot";
          # No RemainAfterExit: the geoblock-cache.path unit starts this unit
          # whenever the fetch publishes new zone data, and a plain start must
          # re-run the script.  Boot-populate still happens via wantedBy below.
          # An nftables restart re-runs it via partOf.  An nftables *reload* is
          # handled by the hook on nftables.service below, because a reload of
          # this inactive unit is a no-op.
          ExecStart = getExe updateSetScript;
          ExecReload = getExe updateSetScript;

          # Only nft needs privileges (CAP_NET_ADMIN); reads /var/lib/geoblock,
          # writes temporary files.  No network, so restrict the address family.
          NoNewPrivileges = true;
          ProtectSystem = true;
          ProtectHome = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectKernelTunables = true;
          ProtectControlGroups = true;
          ProtectKernelModules = true;
          ProtectKernelLogs = true;
          ProtectClock = true;
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          RestrictAddressFamilies = [ "AF_UNIX" "AF_NETLINK" ];
          CapabilityBoundingSet = [ "CAP_NET_ADMIN" ];
          AmbientCapabilities = [ ];
          LockPersonality = true;
          RemoveIPC = true;
          UMask = "0077";
        };
      };

      systemd.services.nftables.serviceConfig.ExecReload = mkAfter [
        (getExe updateSetScript)
      ];

      # Dedicated unprivileged user for the download/update path.  It owns
      # ${cfg.cacheDirectory} (see the tmpfiles rule below) so the fetch can
      # write the zone data and the `.updated` marker itself.  The primary
      # group is nogroup: nothing else needs group access to the cache, so a
      # dedicated group only adds a uid/gid for no benefit.
      users.users.geoblock = {
        isSystemUser = true;
        home = cfg.cacheDirectory;
        description = "ipdeny zone download for geo-blocking";
        group = "nogroup";
      };

      # Create the cache dir owned by geoblock at boot.  This runs on the
      # persistent copy before the impermanence mount, so the ownership sticks.
      # `d` fixes the cache root only.  `Z` repairs the ownership of the zone
      # data below it as well.  The unprivileged `geoblock` user writes that
      # data.  Root-owned data from an older version of this module, which
      # fetched as root, blocks the swap.  The mode stays untouched (`-`).
      # geoblock-fetch sets 0755 and 0644 on the data it publishes.
      systemd.tmpfiles.rules = [
        "d ${cfg.cacheDirectory} 0755 geoblock nogroup -"
        "Z ${cfg.cacheDirectory} - geoblock nogroup -"
      ];

      # When the fetch publishes new zone data (marker touched last), re-run
      # the set update.  Path units do a plain start, which always re-runs this
      # oneshot because geoblock-update-set has no RemainAfterExit.
      systemd.paths.geoblock-cache = {
        description = "Watch for refreshed ipdeny zone data";
        wantedBy = [ "multi-user.target" ];
        pathConfig = {
          PathChanged = "${cfg.cacheDirectory}/.updated";
          Unit = "geoblock-update-set.service";
        };
      };
    };
}
