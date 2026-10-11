# paperless-ngx-mcp — MCP-Server fuer die REST-API von Paperless-ngx
# (github.com/freeformz/paperless-ngx-mcp). Einbindung und Konfiguration:
# modules/mcp-paperless.nix.
#
# WARUM DIESER UND NICHT Knuckles-Team/paperless-ngx-mcp (2026-10-11
# verglichen): Dessen HEAD haengt an `agent-connector-sdk`, das auf PyPI
# nicht existiert, und die installierbare Fassung 1.0.1 zieht 129
# Python-Pakete nach (openai, sentry-sdk, fastapi-cloud-cli …). Dieser hier
# ist reines Go mit vier direkten Abhaengigkeiten; PDF-Seiten rendert er ueber
# PDFium als WebAssembly (go-pdfium + wazero), also ohne cgo und ohne
# Fremd-Binary.
#
# AUF DEN TAG GEPINNT. Der Stand v0.3.3 ist am 2026-10-11 gelesen worden:
# einziges Netzziel ist PAPERLESS_URL (client.go), kein os/exec; der
# Authorization-Kopf faellt bei Weiterleitungen auf einen fremden Host weg
# (client.go:45). Wer `version` anhebt, liest den Unterschied vorher — das
# Programm haelt einen Token mit vollen Rechten auf das Papierarchiv.
#
# go.mod verlangt Go 1.27.1, daher buildGo127Module und nicht buildGoModule
# (der Standard-Go in nixpkgs ist 1.26).
{ lib
, buildGo127Module
, fetchFromGitHub
}:

buildGo127Module rec {
  pname = "paperless-ngx-mcp";
  version = "0.3.3";

  src = fetchFromGitHub {
    owner = "freeformz";
    repo = "paperless-ngx-mcp";
    rev = "v${version}";
    hash = "sha256-YOzBLp7bqaJhQDjuGobwiBs2XE6IKr0hYhssC+V0ko8=";
  };

  # Berechnet 2026-10-11 per `go mod vendor` (Go 1.27.1) und `nix hash path`
  # — nicht aus einem Bau. Stimmt er nicht, nennt der Bau den richtigen.
  vendorHash = "sha256-9wxbWmLfe0hbe9YgrBgPoS8wN+5WDe1M/Iu5z0BJLaI=";

  # Wie das Makefile von upstream: sonst meldet der Server sich als "dev".
  ldflags = [ "-s" "-w" "-X main.version=${version}" ];

  meta = {
    description = "MCP-Server fuer die REST-API von Paperless-ngx";
    homepage = "https://github.com/freeformz/paperless-ngx-mcp";
    license = lib.licenses.mit;
    mainProgram = "paperless-ngx-mcp";
    platforms = lib.platforms.linux;
  };
}
