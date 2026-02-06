# Custom AppArmor Profiles für user-facing Applications
# Provides mandatory access control for Firejail-wrapped apps
{ config, pkgs, lib, ... }:

{
  security.apparmor.policies = {
    # LibreWolf (privacy-focused Firefox fork)
    librewolf.profile = ''
      #include <tunables/global>

      profile librewolf /nix/store/*/bin/librewolf {
        #include <abstractions/base>
        #include <abstractions/fonts>
        #include <abstractions/X>
        #include <abstractions/freedesktop.org>
        #include <abstractions/user-tmp>
        #include <abstractions/dbus-session-strict>
        #include <abstractions/dbus-accessibility-strict>
        #include <abstractions/nameservice>
        #include <abstractions/openssl>
        #include <abstractions/p11-kit>
        #include <abstractions/ssl_certs>

        # Firejail wrapper (LibreWolf is launched via Firejail)
        # Ux = Unconfined execution (Firejail provides its own sandboxing)
        /run/wrappers/bin/firejail Ux,
        /run/wrappers/wrappers.*/firejail Ux,
        /dev/tty rw,
        /run/current-system/sw/bin/bash ix,

        # Nix store executables and libraries
        # rix = read, inherit execute (allows running binaries like the actual librewolf binary)
        # m = memory map (for shared libraries)
        /nix/store/** rix,
        /nix/store/** m,

        # Home directory (restricted)
        owner @{HOME}/.librewolf/** rwk,
        owner @{HOME}/.cache/librewolf/** rwk,
        owner @{HOME}/.cache/mesa_shader_cache/** rwk,
        owner @{HOME}/Downloads/** rw,
        owner @{HOME}/.config/dconf/user rw,
        owner @{HOME}/.config/pulse/ rw,
        owner @{HOME}/.config/pulse/** rwk,
        owner @{HOME}/.config/ibus/** r,

        # Temporary files
        owner /tmp/** rw,
        owner /run/user/*/librewolf/** rw,

        # Full access to user runtime directory (needed for dconf, pulse, wayland)
        owner /run/user/*/ r,
        owner /run/user/*/** rwk,

        /dev/shm/ r,
        /dev/shm/** rw,

        # System files (read-only)
        /etc/hosts r,
        /etc/nsswitch.conf r,
        /etc/resolv.conf r,
        /etc/localtime r,
        /etc/mailcap r,
        /etc/mime.types r,
        /etc/os-release r,
        /etc/alsa/ r,
        /etc/alsa/conf.d/ r,
        /etc/alsa/** r,
        /usr/share/** r,

        # Proc/sys (minimal)
        @{PROC}/@{pid}/fd/ r,
        @{PROC}/@{pid}/mountinfo r,
        @{PROC}/@{pid}/stat r,
        @{PROC}/@{pid}/task/*/stat r,
        @{PROC}/@{pid}/cgroup r,
        @{PROC}/@{pid}/oom_score_adj w,
        @{PROC}/sys/kernel/osrelease r,
        /sys/devices/system/cpu/present r,
        /sys/bus/pci/devices/ r,
        /sys/bus/pci/devices/** r,
        /sys/devices/** r,

        # Audio devices
        /dev/snd/ r,
        /dev/snd/** rw,

        # Deny dangerous paths
        deny @{HOME}/.ssh/** rw,
        deny @{HOME}/.gnupg/** rw,
        deny /etc/shadow r,
        deny /etc/passwd w,
        deny /etc/sudoers* rw,
        deny /var/lib/sops-nix/** r,

        # Network
        network inet stream,
        network inet6 stream,
        network inet dgram,
        network inet6 dgram,
        network netlink raw,

        # DBus (for notifications, portal)
        dbus send
             bus=session
             interface=org.freedesktop.Notifications,
        dbus send
             bus=session
             interface=org.freedesktop.portal.*,
      }
    '';

    # Thunderbird (email client)
    thunderbird.profile = ''
      #include <tunables/global>

      profile thunderbird /nix/store/*/bin/thunderbird {
        #include <abstractions/base>
        #include <abstractions/fonts>
        #include <abstractions/X>
        #include <abstractions/freedesktop.org>
        #include <abstractions/user-tmp>
        #include <abstractions/dbus-session-strict>
        #include <abstractions/nameservice>
        #include <abstractions/openssl>
        #include <abstractions/p11-kit>
        #include <abstractions/ssl_certs>

        # Nix store executables and libraries (read + mmap)
        /nix/store/** rm,

        # Thunderbird profile data
        owner @{HOME}/.thunderbird/** rw,
        owner @{HOME}/.cache/thunderbird/** rw,

        # Email attachments
        owner @{HOME}/Downloads/** rw,

        # Temporary files
        owner /tmp/** rw,
        owner /run/user/*/thunderbird/** rw,

        # System files
        /etc/hosts r,
        /etc/nsswitch.conf r,
        /etc/resolv.conf r,
        /etc/localtime r,
        /etc/mailcap r,
        /etc/mime.types r,
        /usr/share/** r,

        # Proc
        @{PROC}/@{pid}/fd/ r,
        @{PROC}/@{pid}/mountinfo r,
        @{PROC}/@{pid}/stat r,

        # Deny sensitive paths
        deny @{HOME}/.ssh/** rw,
        deny @{HOME}/.gnupg/** rw,
        deny /etc/shadow r,
        deny /var/lib/sops-nix/** r,

        # Network (IMAP/SMTP)
        network inet stream,
        network inet6 stream,
        network inet dgram,
        network inet6 dgram,

        # DBus
        dbus send
             bus=session
             interface=org.freedesktop.Notifications,
      }
    '';

    # VSCodium (code editor)
    vscodium.profile = ''
      #include <tunables/global>

      profile vscodium /nix/store/*/bin/codium {
        #include <abstractions/base>
        #include <abstractions/fonts>
        #include <abstractions/X>
        #include <abstractions/freedesktop.org>
        #include <abstractions/user-tmp>
        #include <abstractions/dbus-session-strict>
        #include <abstractions/nameservice>

        # Firejail wrapper (if VSCodium is launched via Firejail)
        # Ux = Unconfined execution (Firejail provides its own sandboxing)
        /run/wrappers/bin/firejail Ux,
        /run/wrappers/wrappers.*/firejail Ux,
        /dev/tty rw,
        /run/current-system/sw/bin/bash ix,

        # Nix store executables and libraries (read + mmap)
        /nix/store/** rm,

        # VSCodium config and extensions
        owner @{HOME}/.config/VSCodium/** rw,
        owner @{HOME}/.vscode-oss/** rw,
        owner @{HOME}/.cache/vscode-oss/** rw,

        # Workspace (full access to home for development)
        owner @{HOME}/** rw,
        owner @{HOME}/nixos-config/** rw,
        owner @{HOME}/Projects/** rw,

        # Temporary files
        owner /tmp/** rw,

        # System files
        /etc/** r,
        /usr/share/** r,

        # Proc
        @{PROC}/** r,
        /sys/** r,

        # Deny secrets even with broad home access
        deny /var/lib/sops-nix/** r,
        deny @{HOME}/.gnupg/private-keys-v1.d/** r,

        # Network (for extensions)
        network inet stream,
        network inet6 stream,

        # PTY for terminals
        capability sys_ptrace,
        ptrace read,

        # Execute development tools
        /nix/store/*/bin/* rix,
      }
    '';

    # Spotify (music streaming)
    spotify.profile = ''
      #include <tunables/global>

      profile spotify /nix/store/*/bin/spotify {
        #include <abstractions/base>
        #include <abstractions/fonts>
        #include <abstractions/X>
        #include <abstractions/freedesktop.org>
        #include <abstractions/user-tmp>
        #include <abstractions/dbus-session-strict>
        #include <abstractions/audio>
        #include <abstractions/nameservice>
        #include <abstractions/openssl>

        # Nix store executables and libraries (read + mmap)
        /nix/store/** rm,

        # Spotify config and cache
        owner @{HOME}/.config/spotify/** rw,
        owner @{HOME}/.cache/spotify/** rw,

        # Temporary files
        owner /tmp/** rw,

        # System files
        /etc/hosts r,
        /etc/nsswitch.conf r,
        /etc/resolv.conf r,
        /etc/localtime r,
        /usr/share/** r,

        # Audio devices
        /dev/snd/** rw,

        # Proc
        @{PROC}/@{pid}/** r,

        # Deny everything else in home
        deny @{HOME}/** rw,
        audit deny @{HOME}/.ssh/** rw,
        audit deny /var/lib/sops-nix/** r,

        # Network
        network inet stream,
        network inet6 stream,
        network inet dgram,

        # DBus
        dbus send
             bus=session
             interface=org.freedesktop.Notifications,
      }
    '';

    # Discord (chat application)
    discord.profile = ''
      #include <tunables/global>

      profile discord /nix/store/*/bin/Discord {
        #include <abstractions/base>
        #include <abstractions/fonts>
        #include <abstractions/X>
        #include <abstractions/freedesktop.org>
        #include <abstractions/user-tmp>
        #include <abstractions/dbus-session-strict>
        #include <abstractions/audio>
        #include <abstractions/nameservice>
        #include <abstractions/openssl>

        # Nix store executables and libraries (read + mmap)
        /nix/store/** rm,

        # Discord config
        owner @{HOME}/.config/discord/** rw,
        owner @{HOME}/.config/Discord/** rw,

        # Downloads (for file sharing)
        owner @{HOME}/Downloads/** rw,

        # Temporary files
        owner /tmp/** rw,

        # System files
        /etc/hosts r,
        /etc/nsswitch.conf r,
        /etc/resolv.conf r,
        /etc/localtime r,
        /usr/share/** r,

        # Audio/video devices
        /dev/snd/** rw,
        /dev/video* rw,

        # Proc
        @{PROC}/@{pid}/** r,

        # Deny sensitive areas
        deny @{HOME}/.ssh/** rw,
        deny @{HOME}/.gnupg/** rw,
        deny /var/lib/sops-nix/** r,

        # Network
        network inet stream,
        network inet6 stream,
        network inet dgram,
        network netlink raw,

        # DBus
        dbus send
             bus=session
             interface=org.freedesktop.Notifications,
      }
    '';
  };
}
