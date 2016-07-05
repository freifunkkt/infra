{ pkgs, lib, ... }:

{
  config = {

    time.timeZone = "UTC";

    boot =
      { kernel.sysctl."net.ipv6.conf.default.autoconf" = 0;
        kernel.sysctl."net.ipv6.conf.all.autoconf" = 0;
        tmpOnTmpfs = true;
        kernelPackages = pkgs.linuxPackages_latest;
      };

    networking.firewall.allowPing = true;
    networking.wireless.enable = false;

    services =
      { atd.enable = false;
        nscd.enable = false;
        udisks2.enable = false;
        haveged.enable = true;

        ntp.enable = false;
        chrony =
          { enable = true;
            servers =
              [ "0.de.pool.ntp.org"
                "1.de.pool.ntp.org"
                "2.de.pool.ntp.org"
                "3.de.pool.ntp.org"
              ];
          };

        openssh =
          { enable = true;
            hostKeys =
              [ { type = "ed25519";
                  path = "/etc/ssh/ssh_host_ed25519_key";
                  bits = 256;
                }
                { type = "rsa";
                  path = "/etc/ssh/ssh_host_rsa_key";
                  bits = 2048;
                }
              ];
          };

        journald.extraConfig =
          ''
            MaxFileSec=1day
            MaxRetentionSec=1week
          '';
      };

    environment.systemPackages = with pkgs;
      [ vim htop git ethtool python3
        tcpdump iptables jnettop
      ];

    programs.bash.enableCompletion = true;

    hardware.pulseaudio.enable = false;

    fonts.fontconfig.enable = false;

    security =
      { polkit.enable = false;
        rngd.enable = false;
      };

    users.mutableUsers = false;
    users.extraUsers.root.password = lib.mkDefault "";
    users.extraUsers.root.openssh.authorizedKeys.keys =
      [ 
        "ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAIEA5CIF10pzSxjbEZ4ulU80lm5xRgmLg7PcCY6NdzlQDQvT0GIoFleoglODKAXas4y0AfdU7B0QFL8ect0DCrLzZR50kVL8Z2xd3dAsK3HZnhu7ZikAHwdfn55nX5SbBWdC4g9xi1Hg0qEfip62gFh5vP70i6bG+gy9JfPHyYnS7N8= Andreas"
      ];

    i18n =
      { consoleKeyMap = "us";
        defaultLocale = "en_US.UTF-8";
        supportedLocales = [ "en_US.UTF-8/UTF-8" ];
      };

    nix =
      { extraOptions =
          ''
            auto-optimise-store = true
          '';
        gc =
          { automatic = true;
            options = "--delete-older-than 2d";
          };
        binaryCaches =
          [ "https://hydra.mayflower.de/"
          ];
        binaryCachePublicKeys =
          [ "hydra.mayflower.de:9knPU2SJ2xyI0KTJjtUKOGUVdR2/3cOB4VNDQThcfaY="
          ];
      };

    nixpkgs.config = {
      packageOverrides = pkgs: {
        collectd = pkgs.collectd.override {
          jdk = null;
          libdbi = null;
          cyrus_sasl = null;
          libmodbus = null;
          libnotify = null;
          gdk_pixbuf = null;
          libsigrok = null;
          libvirt = null;
          rabbitmq-c = null;
          riemann = null;
          rrdtool = null;
          varnish = null;
          yajl = null;
        };
      };
    };
  };
}
