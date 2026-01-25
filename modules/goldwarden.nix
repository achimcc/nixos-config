# Goldwarden - Sicherer Bitwarden-kompatibler Desktop-Client
# Fokus auf Cybersecurity: Memory Protection, Polkit Auth, Service Hardening
#
# Sicherheitsfeatures:
# - Vault-Inhalt wird verschlüsselt im RAM gehalten (memguard)
# - Kernel-Level Memory Protection für Schlüssel
# - Biometrische Authentifizierung via Polkit
# - Systemd Sandboxing (Namespaces, Seccomp, Capabilities)
# - Integration mit Browser via Native Messaging
#
# Hinweis: Firejail wird NICHT verwendet, da:
# - Kein offizielles Firejail-Profil für Goldwarden existiert
# - Goldwarden D-Bus/Polkit-Zugriff für Biometrie benötigt
# - Goldwarden selbst bereits Memory Protection bietet (memguard)

{ config, lib, pkgs, ... }:

{
  # ==========================================
  # GOLDWARDEN PROGRAMM-KONFIGURATION
  # ==========================================

  programs.goldwarden = {
    enable = true;
    # SSH-Agent deaktiviert - GPG-Agent wird stattdessen verwendet
    useSshAgent = false;
  };

  # ==========================================
  # POLKIT-REGELN FÜR SICHERE AUTHENTIFIZIERUNG
  # ==========================================

  # Goldwarden nutzt Polkit für biometrische Entsperrung
  # Diese Regel erlaubt dem Benutzer, den Vault mit Fingerprint zu entsperren
  security.polkit.extraConfig = ''
    // Goldwarden Biometric Authentication
    // Erlaubt Benutzern in der "wheel" Gruppe, Goldwarden ohne Passwort zu entsperren
    // wenn biometrische Authentifizierung (Fingerprint) verfügbar ist
    polkit.addRule(function(action, subject) {
      if (action.id === "com.quexten.goldwarden.unlock" ||
          action.id === "com.quexten.goldwarden.ssh" ||
          action.id === "com.quexten.goldwarden.browserbiometrics") {
        if (subject.isInGroup("wheel")) {
          return polkit.Result.AUTH_SELF;
        }
      }
    });
  '';

  # ==========================================
  # SYSTEMD SERVICE HARDENING
  # ==========================================

  # Überschreibt den User-Service mit zusätzlichem Sandboxing
  systemd.user.services.goldwarden = {
    # Service-Definition kommt vom Goldwarden-Modul
    # Hier fügen wir zusätzliche Sicherheitshärtung hinzu
    serviceConfig = {
      # ---- Namespace Isolation ----
      # Private /tmp verhindert Zugriff auf temporäre Dateien anderer Prozesse
      PrivateTmp = true;

      # Verhindert Zugriff auf /home anderer Benutzer
      ProtectHome = "read-only";

      # Macht Systemverzeichnisse read-only
      ProtectSystem = "strict";

      # Isoliert Netzwerk-Namespace nicht (benötigt für Bitwarden-API)
      # PrivateNetwork = false; # Standard

      # ---- Capabilities ----
      # Keine zusätzlichen Capabilities benötigt
      CapabilityBoundingSet = "";
      AmbientCapabilities = "";
      NoNewPrivileges = true;

      # ---- Seccomp Filter ----
      # Erlaubt nur notwendige Syscalls
      SystemCallFilter = [
        "@system-service"
        "~@privileged"
        "~@resources"
      ];
      SystemCallArchitectures = "native";

      # ---- Weitere Härtung ----
      # Verhindert Speicher-Ausführung
      MemoryDenyWriteExecute = true;

      # Kein Zugriff auf Kernel-Module
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectKernelLogs = true;

      # Kein Zugriff auf Control Groups
      ProtectControlGroups = true;

      # Verhindert Änderung der Prozess-Personality
      LockPersonality = true;

      # Restrict address families to what's needed
      RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];

      # Restrict namespaces
      RestrictNamespaces = true;

      # Restrict realtime scheduling
      RestrictRealtime = true;

      # Umask für erstellte Dateien (nur Owner kann lesen/schreiben)
      UMask = "0077";
    };
  };

  # ==========================================
  # SICHERHEITS-HINWEISE UND BEST PRACTICES
  # ==========================================

  # Goldwarden Configuration Reminder
  # Nach der Installation:
  #
  # 1. Initialisierung:
  #    goldwarden setup wizard
  #
  # 2. Anmeldung bei Bitwarden:
  #    goldwarden login
  #
  # 3. PIN setzen (für lokale Entsperrung):
  #    goldwarden pin set
  #
  # 4. Biometrische Entsperrung aktivieren (optional):
  #    goldwarden vault unlock --biometric
  #
  # 5. Browser-Erweiterung:
  #    - Bitwarden Browser Extension installieren
  #    - In Extension: Einstellungen > Andere > "Unlock with Biometrics"
  #
  # Sicherheitstipps:
  # - Verwende eine starke PIN (mindestens 6 Ziffern)
  # - Aktiviere 2FA auf deinem Bitwarden-Konto
  # - Überprüfe regelmäßig: goldwarden status
}
