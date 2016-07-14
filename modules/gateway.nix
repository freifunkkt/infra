{ config, lib, pkgs, ... }:

with lib;

let
  ffpkgs = (import ../pkgs/default.nix) { };

  cfg = config.freifunk.gateway;

  mapSegments = f: mapAttrsToList f cfg.segments;
  concatSegments = f: concatStrings (mapSegments f);

  genMacAddr = base: prefix: "${prefix}:${base}";

  mkFastd = { interface, mtu, bind, secret, mac, segment }:
    {
      description = "fastd tunneling daemon for ${interface}";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      script = ''
        mkdir -p /run/fastd
        rm -f /run/fastd/${interface}.sock
        chown nobody:nogroup /run/fastd

        exec ${ffpkgs.fastd}/bin/fastd \
          --status-socket /run/fastd/${interface}.sock \
          --user nobody \
          --group nogroup \
          --log-level verbose \
          --mode tap \
          --interface "${interface}" \
          --mtu ${toString mtu} \
          ${concatMapStrings (b: ''
            --bind '${b}' \'') bind}
          --method salsa2012+umac \
          --on-up '${pkgs.iproute}/bin/ip link set "${interface}" ${lib.optionalString (mac != null) "address ${mac}"} up; ${pkgs.batctl}/bin/batctl -m bat-${segment} if add "${interface}"; systemctl start bat-${segment}-netdev.service;' \
          --on-verify "true" \
          --config ${pkgs.writeText "fastd-mesh-${segment}" ''
            secret "${secret}";
          ''} \
          --config-peer ${pkgs.writeText "some-peer" ''
            key "2242fe7fff1def15233a364487545e57c3c69e1b624d97bd5d72359b9851cb6e";
            float yes;
          ''}
      '';
    };

in

{
  options = {
    freifunk.gateway = {
      enable = mkEnableOption "Freifunk Gateway Config";

      externalInterface = mkOption {
        type = types.str;
        description = "External Interface";
        example = "eth0";
      };

      ip4Interfaces = mkOption {
        type = types.listOf types.str;
        description = "Interfaces to route IPv4 to";
        example = "tun0";
      };

      ip6Interface = mkOption {
        type = types.str;
        description = "Interface to route IPv6 to";
        example = "eth1";
      };

      networkingLocalCommands = mkOption {
        type = types.lines;
        description = "Commands to add to networking.localCommands";
        default = "";
      };

      segments = mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            baseMacAddress = mkOption {
              type = types.str;
              description = "Base MAC address without first byte";
              example = "80:00:01:23:42";
            };

            bridgeInterface = mkOption {
              type = types.attrs;
              description = "Interface config for main bridge";
              example = {
                ip4 = [ { address = "10.80.0.11"; prefixLength = 19; } ];
                ip6 = [ { address = "fdef:ffc0:4fff::11"; prefixLength = 64; } ];
              };
            };

            dhcpRanges = mkOption {
              type = types.listOf types.str;
              description = "List of DHCP ranges in dnsmasq format";
              example = [ "10.80.1.0,10.80.7.255,255.255.224.0,1h" ];
            };

            portBalancings = mkOption {
              type = types.listOf types.attrs;
              description = "Simple port balancing mappings";
              default = [];
            };

            ra.prefixes = mkOption {
              type = types.listOf types.str;
              default = [];
            };

            ra.rdnss = mkOption {
              type = types.listOf types.str;
              default = [];
            };

            fastdConfigs = mkOption {
              type = types.attrsOf (types.submodule {
                options = {
                  listenAddresses = mkOption {
                    type = types.listOf types.str;
                    default = [ "any" ];
                  };
                  listenPort = mkOption {
                    type = types.int;
                    default = 10000;
                  };
                  mac = mkOption {
                    type = types.nullOr types.str;
                    default = null;
                  };
                  secret = mkOption {
                    type = types.str;
                    description = "Secret key for fastd";
                    example = "180dcd09cd9e40f18b202d0a5c5c2d174fbb7758defc0a60bc649016c74c4d42";
                  };
                  mtu = mkOption {
                    type = types.int;
                    default = 1280;
                  };
                };
              });
              description = "Configurion for fastd daemons";
            };
          };
        });
        description = "Freifunk Segments configuration";
      };

      graphite.host = mkOption {
        type = types.str;
        description = "Graphite hostname to deliver stats to";
        example = "stats.example.com";
      };

      graphite.port = mkOption {
        type = types.int;
        description = "Graphite TCP port to deliver stats to";
        example = 2003;
      };
    };
  };

  config = mkIf cfg.enable {

    boot =
      { extraModulePackages = with config.boot.kernelPackages;
          #removed netatop in next line; currently broken in nixos unstable
          [ batman_adv ];
        kernelModules = [ "batman_adv" ];
        tmpOnTmpfs = true;
        kernel.sysctl =
          { "kernel.panic" = 1;
            "fs.file-max" = 100000;
            "vm.swappiness" = 10;
            "net.core.default_qdisc" = "fq_codel";
            "net.ipv4.ip_forward" = 1;
            "net.ipv6.conf.all.forwarding" = 1;
            "net.ipv6.conf.all.use_tempaddr" = 0;
            "net.ipv6.conf.default.use_tempaddr" = 0;
            "net.ipv4.conf.default.rp_filter" = 2;
            "net.ipv4.conf.all.rp_filter" = 2;
            # Increase Linux autotuning TCP buffer limits
            # Set max to 16MB for 1GE
            "net.core.rmem_max" = 16777216;
            "net.core.wmem_max" = 16777216;
            "net.core.rmem_default" = 16777216;
            "net.core.wmem_default" = 16777216;
            "net.core.optmem_max" = 40960;
            "net.ipv4.tcp_rmem" = "4096 87380 16777216";
            "net.ipv4.tcp_wmem" = "4096 65536 16777216";
            # Make room for more TIME_WAIT sockets due to more clients,
            # and allow them to be reused if we run out of sockets
            # Also increase the max packet backlog
            "net.core.netdev_max_backlog" = 50000;
            "net.ipv4.tcp_max_syn_backlog" = 30000;
            "net.ipv4.tcp_max_tw_buckets" = 2000000;
            "net.ipv4.tcp_tw_reuse" = 1;
            "net.ipv4.tcp_fin_timeout" = 10;
            # Increase garbage collection thresholds for neighbor tables
            "net.ipv4.neigh.default.gc_thresh1" = 8192;
            "net.ipv4.neigh.default.gc_thresh2" = 9216;
            "net.ipv4.neigh.default.gc_thresh3" = 10240;
            "net.ipv6.neigh.default.gc_thresh1" = 8192;
            "net.ipv6.neigh.default.gc_thresh2" = 9216;
            "net.ipv6.neigh.default.gc_thresh3" = 10240;
            "net.ipv6.route.gc_thresh" = 10240;
            # Disable TCP slow start on idle connections
            "net.ipv4.tcp_slow_start_after_idle" = 0;
            # Disable source routing and redirects
            "net.ipv4.conf.all.send_redirects" = 0;
            "net.ipv4.conf.all.accept_redirects" = 0;
            "net.ipv6.conf.all.accept_redirects" = 0;
            "net.ipv4.conf.all.accept_source_route" = 0;
            "net.ipv6.conf.all.accept_source_route" = 0;
            # Log martian packets
            "net.ipv4.conf.all.log_martians" = 1;
            # Decrease connection tracking timeouts
            "net.netfilter.nf_conntrack_generic_timeout" = 300;
            "net.netfilter.nf_conntrack_tcp_timeout_established" = 3600;
            "net.netfilter.nf_conntrack_expect_max" = 8192;
          };
      };

    networking =
      { firewall = {
          allowedTCPPorts = [ 5201 69 ];
          allowedUDPPorts = [ 69 ];
          checkReversePath = false;
          # ports direkt raus:
          # im folgenden habe ich die Ports für udp entfernt: 655 (unbekannt) 1149 (unbekannt)
          # folgende Ports sind noch drin: 
          # udp: 53 -> DNS, 123 -> NTP, 4500 -> ipsec, 1293 -> IPsec, 500 -> IPsec, 5060 -> Voice over IP, 5061 -> encrypted VOIP, 4569 -> Asterisk, 3478 -> Voip/PS3
          # im folgenden habe ich die Ports für tcp entfernt: 655 (unbekannt) 1149 (unbekannt)
          # tcp: 80-> http, 443-> https, 143 -> imap, 993 -> imaps, 110 -> POP3, 587 -> SMTP, 5222, 5269 XMPP(Jabber),
          #      123 -> NTP, 4500 -> ipsec, 1293 -> IPsec, 500 -> IPsec, 5060 -> Voice over IP, 5061 -> encrypted VOIP,
          #      4569 -> Asterisk, 3478 -> Voip/PS3
          
          extraCommands = ''
            ${concatSegments (name: scfg: ''
              iptables -I nixos-fw 3 -i br-${name} -p udp --dport 67:68 --sport 67:68 -j nixos-fw-accept
              ip46tables -I nixos-fw 3 -i br-${name} -p udp --dport 53 -j nixos-fw-accept
              ip46tables -I nixos-fw 3 -i br-${name} -p tcp --dport 53 -j nixos-fw-accept

              ${concatMapStrings (port: ''
                iptables -A PREROUTING -t mangle -i br-${name} -p udp --dport ${toString port} -j MARK --set-mark 5
              '') [ 53 123 4500 1293 500 5060 5061 4569 3478 ]}

              ${concatMapStrings (port: ''
                iptables -A PREROUTING -t mangle -i br-${name} -p tcp --dport ${toString port} -j MARK --set-mark 5
              '') [ 80 443 143 993 110 587 5222 5269 53 123 4500 1293 500 5060 5061 4569 3478 ]}

              ${concatStrings (mapAttrsToList (name: fcfg: ''
                ip46tables -I nixos-fw 3 -i ${cfg.externalInterface} -p udp --dport ${toString fcfg.listenPort} -j nixos-fw-accept
              '') scfg.fastdConfigs)}
            '')}

            ip46tables -F FORWARD
            ip46tables -P FORWARD DROP
            ip46tables -A FORWARD -i br-+ -o br-+ -j ACCEPT
            ${concatSegments (name: scfg: ''
              ip6tables -A FORWARD -i br-${name} -o ${cfg.ip6Interface} -j ACCEPT
              ip6tables -A FORWARD -i ${cfg.ip6Interface} -o br-${name} -j ACCEPT
            '' + (concatMapStrings (if4: ''
              iptables -A FORWARD -i br-${name} -o ${if4} -j ACCEPT
              iptables -A FORWARD -i ${if4} -o br-${name} -j ACCEPT
            '') cfg.ip4Interfaces))}
            iptables -A FORWARD -j REJECT --reject-with icmp-admin-prohibited
            ip6tables -A FORWARD -j REJECT --reject-with icmp6-adm-prohibited

            iptables -t nat -F PREROUTING
            iptables -t nat -F POSTROUTING
            ip46tables -t mangle -F POSTROUTING

            ${concatSegments (name: scfg: concatStrings (map ({ from, to }: ''
              ip46tables -t nat -A PREROUTING -i ${cfg.externalInterface} -p udp -m udp --dport ${toString from} -m u32 --u32 "0xc&0x1=0x1" -j REDIRECT --to-ports ${toString to}
            '') scfg.portBalancings))}

            ${concatMapStrings (if4: ''
              iptables -t nat -A POSTROUTING -o ${if4} -j MASQUERADE
              iptables -t mangle -A POSTROUTING -o ${if4} -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1200
            '') cfg.ip4Interfaces}
          '';
        };
        bridges = fold (a: b: a // b) {} (mapSegments (name: scfg: {
          "br-${name}" = {
            interfaces = [];
          };
        }));
        interfaces = fold (a: b: a // b) {} (mapSegments (name: scfg: {
          "br-${name}" = {
            macAddress = genMacAddr scfg.baseMacAddress "f6";
          } // scfg.bridgeInterface;
        }));
        dhcpcd.allowInterfaces = [ ];
        localCommands = ''
          ip route replace unreachable default metric 100 table 42
          ${concatSegments (name: scfg: ''
            ip rule add iif br-${name} lookup 42
            ip rule add iif br-${name} fwmark 5 lookup 5
          '')}
          ${cfg.networkingLocalCommands}
        '';
      };

    systemd.services = fold (a: b: a // b) {} (
      mapSegments (name: scfg: {
        "bat-${name}-netdev" = {
          description = "batman interface bat-${name}";
          #wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
          #after = [ "br0-netdev.service" ];
          #requires = [ "br-${name}-netdev.service" ];

          serviceConfig.Type = "oneshot";
          path = with pkgs; [ iproute batctl ];
          script = ''
            batctl -m bat-${name} gw server 1000000/1000000
            batctl -m bat-${name} it 10000
            ip link set bat-${name} down
            ip link set bat-${name} address ${genMacAddr scfg.baseMacAddress "fa"}
            ip link set bat-${name} up
            ip link set br-${name} down
            ip link set bat-${name} master br-${name}
            ip link set br-${name} up
            systemctl restart network-addresses-br-${name}.service
            systemctl start alfred-${name}.service batadv-vis-${name}.service
          '';
        };
        "alfred-${name}" = {
          description = "Alfred daemon for ${name}";
          after = [ "network.target" ];

          script = ''
            sleep 2
            exec ${pkgs.alfred}/bin/alfred -i br-${name} -b bat-${name} -u /run/alfred-${name}.sock
          '';
        };
        "batadv-vis-${name}" = {
          description = "batadv-vis daemon for ${name}";
          after = [ "alfred-${name}.service" ];
          requires = [ "alfred-${name}.service" ];

          script = "exec ${pkgs.alfred}/bin/batadv-vis -s -i bat-${name} -u /run/alfred-${name}.sock";
        };
      } // (fold (a: b: a // b) {} (mapAttrsToList (interface: fcfg: {
        "fastd-${name}-${interface}" = mkFastd {
          inherit (fcfg) secret mac mtu;
          bind = map (addr: "${addr}:${toString fcfg.listenPort}") fcfg.listenAddresses;
          interface = "${name}-${interface}";
          segment = name;
        };
      }) scfg.fastdConfigs))
    ))
    //
    {
      iperf = {
        description = "iperf daemon";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        serviceConfig.ExecStart = "${pkgs.iperf}/bin/iperf -s -p 5201";
      };
    };

    environment.systemPackages = with pkgs;
      [ vim
        wget
        tcpdump
        htop
        batctl
        alfred
        ffpkgs.ecdsautils
        ffpkgs.fastd
        atop
        bridge-utils
        strace
        socat
        jq
        jnettop
        tmux
        mtr
        iperf
        bmon
      ];

    services =
      { dnsmasq =
          { enable = true;
            extraConfig = ''
              bind-interfaces
              interface=lo
              ${concatSegments (name: scfg: ''
                interface=br-${name}
              '')}

              dhcp-ignore-names
              dhcp-lease-max=40960
              ${concatSegments (name: scfg: concatMapStrings (range: ''
                dhcp-range=${range}
              '') scfg.dhcpRanges)}

              no-hosts
              dns-forward-max=1024
              cache-size=0
              no-negcache
              no-resolv
              server=213.73.91.35

              enable-tftp
              tftp-root=/var/lib/tftp
              tftp-secure
              dhcp-match=set:ipxe,175
              dhcp-boot=tag:!ipxe,undionly.kpxe
            '';
          };
        unbound =
          { enable = true;
            allowedAccess = [ "::1" "127.0.0.1" ];
            extraConfig = ''
              server:
                port: 54
                num-threads: 4
                msg-cache-size: 16M
                msg-cache-slabs: 8
                num-queries-per-thread: 2048
                rrset-cache-size: 16M
                rrset-cache-slabs: 8
                cache-min-ttl: 10
                cache-max-ttl: 86400
                cache-max-negative-ttl: 600
                qname-minimisation: yes
                prefetch: yes
                hide-version: yes
                log-queries: no
            '';
          };
        radvd = let
          config = concatSegments (name: scfg:
            lib.optionalString (scfg.ra.prefixes != []) ''
              interface br-${name} {
                AdvSendAdvert on;
                MaxRtrAdvInterval 300;

                ${concatStrings (map (prefix: ''
                  prefix ${prefix} {
                    AdvValidLifetime 600;
                    AdvPreferredLifetime 150;
                    DeprecatePrefix on;
                  };
                '') scfg.ra.prefixes)}

                ${concatStrings (map (dns: ''
                  RDNSS ${dns} { };
                '') scfg.ra.rdnss)}
              };
          '');
          in
          { enable = (config != "");
            inherit config;
          };
        collectd =
          { enable = true;
            extraConfig = ''
              FQDNLookup true
              Interval 30

              LoadPlugin conntrack
              LoadPlugin cpu
              LoadPlugin df
              LoadPlugin disk
              LoadPlugin dns
              LoadPlugin entropy
              LoadPlugin interface
              LoadPlugin load
              LoadPlugin memory
              LoadPlugin processes
              LoadPlugin swap
              LoadPlugin users
              LoadPlugin write_graphite

              <Plugin df>
                FSType rootfs
                FSType sysfs
                FSType proc
                FSType devtmpfs
                FSType devpts
                FSType tmpfs
                FSType fusectl
                FSType cgroup
                IgnoreSelected true
              </Plugin>

              <Plugin dns>
              ${concatSegments (name: scfg: ''
                Interface "br-${name}"
              '')}
              </Plugin>

              <Plugin interface>
                Interface "lo"
                IgnoreSelected true
              </Plugin>

              <Plugin write_graphite>
                <Node "${cfg.graphite.host}">
                  Host "${cfg.graphite.host}"
                  Port "${toString cfg.graphite.port}"
                  Protocol "tcp"
                  LogSendErrors true
                  Prefix "servers."
                  StoreRates true
                  AlwaysAppendDS false
                  SeparateInstances false
                  EscapeCharacter "_"
                </Node>
              </Plugin>
            '';
          };
      };
    };
}
