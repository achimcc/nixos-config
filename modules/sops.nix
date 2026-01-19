# Sops-nix Secret Management
# Verschlüsselte Secrets im Git Repository

{ config, lib, pkgs, ... }:

{
  # ==========================================
  # SOPS GRUNDKONFIGURATION
  # ==========================================

  sops = {
    # Standard Secrets-Datei
    defaultSopsFile = ../secrets/secrets.yaml;
    defaultSopsFormat = "yaml";

    # Age Key aus SSH Host Key ableiten
    age = {
      # SSH Host Key wird automatisch zu Age Key konvertiert
      sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
      # Alternativ: Eigener Age Key
      keyFile = "/var/lib/sops-nix/key.txt";
      # Key generieren falls nicht vorhanden
      generateKey = true;
    };

    # ==========================================
    # SECRETS DEFINITIONEN
    # ==========================================

    # Beispiel: API Keys, Passwörter, etc.
    # Diese werden nach /run/secrets/<name> entschlüsselt

    # Beispiel Secret (auskommentiert bis secrets.yaml existiert)
    # secrets.example-secret = {};
    
    # Secret mit spezifischen Berechtigungen
    # secrets.service-api-key = {
    #   owner = "serviceuser";
    #   group = "servicegroup";
    #   mode = "0440";
    # };

    # Secret das einen Dienst neu startet bei Änderung
    # secrets.important-config = {
    #   restartUnits = [ "myservice.service" ];
    # };

    # Secret an bestimmten Pfad verlinken
    # secrets.app-secret = {
    #   path = "/var/lib/myapp/secret.key";
    # };
  };

  # Sops CLI Tool verfügbar machen
  environment.systemPackages = with pkgs; [
    sops
    age
    ssh-to-age
  ];
}
