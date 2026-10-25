# Zwei Skills zur Aktienanalyse, beide fuer OpenClaw geschrieben und upstream
# mit `npx -y skills add … --agent claude-code` installiert: ein ungepinntes
# npm-Werkzeug klont HEAD nach ~/.claude/skills, danach verlangen die Skills
# `pip install` bzw. `uv run` mit Abhaengigkeiten, die zur Laufzeit
# ungepinnt aus PyPI kommen. Hier statt dessen dieselbe Bauart wie
# modules/claude-obsidian.nix: `fetchFromGitHub` mit Rev und Hash, fehlende
# Python-Pakete als Wheel von PyPI mit Hash, kein npx, kein pip, kein uv.
#
# Beide Repos haben KEINE Lizenz — darum keine Kopie in diesem Repo (wie bei
# den secskills in claude-skills.nix), sondern der gepinnte Abruf. Wer einen
# Rev hebt, liest vorher den Diff der Skripte.
#
#  - stock-analyzer (github.com/feiyuggg/openclaw-stock-analyzer, Rev a127786,
#    Einzelpfleger). Fuenf-Dimensionen-Bewertung nach Buffett/Duan Yongping,
#    DCF, PEG, Optionen. GELESEN 2026-10-25: SKILL.md, METHODOLOGY.md, drei
#    Python-Skripte. Netz nur zu Yahoo Finance (yahooquery) und SEC EDGAR;
#    schreibt nur mit `--save`/`--out`. Befehle: analyze-stock, analyze-value,
#    analyze-earnings.
#
#  - stock-analysis (github.com/sundial-org/awesome-openclaw-skills, Rev
#    b80cde2, Unterordner skills/stock-analysis; eine Sammlung von ~900
#    Skills, genommen wird nur dieser). Acht Dimensionen, Krypto, Portfolios.
#    GELESEN 2026-10-25: SKILL.md und scripts/ (analyze_stock.py,
#    portfolio.py). Netz zu Yahoo Finance (yfinance), CNN Fear & Greed,
#    Google-News-RSS; schreibt Portfolios und sonst nichts. TODO.md und
#    App-Plan.md (Notizen des Autors) kommen NICHT in den Skill-Ordner — sie
#    braeuchte niemand im Kontext. Befehle: stock-analysis, stock-portfolio.
#    Portfolios unter ~/.local/share/stock-analysis statt ~/.clawdbot.
#    OHNE edgartools (nicht in nixpkgs, 22 Abhaengigkeiten, darunter welche,
#    die ebenfalls fehlen): Das Insider-Signal (SEC Form 4) faellt weg; das
#    Skript faengt den ImportError ab und normiert die Gewichte neu.
#
# In beiden SKILL.md ersetzt der Bau die Installations- und Aufrufzeilen
# (pip, PATH, `uv run {baseDir}/…`) durch die Befehle im PATH, damit das
# Modell nichts nachinstalliert.
{ lib, pkgs, id, ... }:

let
  py = pkgs.python3Packages;

  # --- stock-analyzer ---------------------------------------------------------

  quelleAnalyzer = pkgs.fetchFromGitHub {
    owner = "feiyuggg";
    repo = "openclaw-stock-analyzer";
    rev = "a127786a7137f12f7e6ce9d2771dcedde7ca50bd";
    hash = "sha256-5xEqwWAU+LCXDxCw82yPY78ttUJt2dHSjqwkQCtdK18=";
  };

  yahooquery = py.buildPythonPackage rec {
    pname = "yahooquery";
    version = "2.4.1";
    format = "wheel";
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/ab/98/bd176685b2175fa7a5283e2fc73a9a7338715015849c904cca6eb69b5082/yahooquery-${version}-py3-none-any.whl";
      hash = "sha256-7m/5ucSrajQSXh1VxkEqYWlIVZQBJn5hck6NvamKLYs=";
    };
    dependencies = with py; [
      beautifulsoup4
      curl-cffi
      lxml
      pandas
      requests-futures
      tqdm
    ];
    pythonImportsCheck = [ "yahooquery" ];
  };

  pythonAnalyzer = pkgs.python3.withPackages (p: [
    yahooquery
    p.requests
  ]);

  stockAnalyzer = pkgs.stdenvNoCC.mkDerivation {
    pname = "stock-analyzer";
    version = "0-unstable-2026-02-22";
    src = quelleAnalyzer;
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin $out/skill
      for skript in analyze-stock analyze-value analyze-earnings; do
        { echo "#!${pythonAnalyzer}/bin/python3"; tail -n +2 "$skript"; } > "$out/bin/$skript"
        chmod +x "$out/bin/$skript"
      done
      cp SKILL.md METHODOLOGY.md $out/skill/
      substituteInPlace $out/skill/SKILL.md \
        --replace-fail '# 确保依赖已安装' '# Bereits per Nix installiert (~/nixos-config/modules/claude-aktien-skills.nix):' \
        --replace-fail 'pip install yahooquery' '# analyze-stock, analyze-value und analyze-earnings stehen im PATH, yahooquery ist dabei.' \
        --replace-fail '# 添加到 PATH' '# Kein pip, kein PATH-Eintrag noetig.' \
        --replace-fail 'export PATH="$HOME/.openclaw/workspace/skills/stock-analyzer:$PATH"' ""
      runHook postInstall
    '';
  };

  # --- stock-analysis ---------------------------------------------------------

  quelleAnalysis = pkgs.fetchFromGitHub {
    owner = "sundial-org";
    repo = "awesome-openclaw-skills";
    rev = "b80cde2ef85241dd4fd54a1b934f5e22835f78ba";
    hash = "sha256-x+Vd7tXosRxvWdLhiuPD57YC3lpURZZnVKc5PLGg874=";
  };

  fear-and-greed = py.buildPythonPackage rec {
    pname = "fear-and-greed";
    version = "0.4";
    format = "wheel";
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/4a/be/cbcdc55b93bb7207a63015ad21a5fd7697f7010657c9d2aab8d70310c740/fear_and_greed-${version}-py3-none-any.whl";
      hash = "sha256-8V+9POiXYsFdhkm1bkOsqhZCTJxQE++oltYaPX+GM4Y=";
    };
    dependencies = with py; [
      requests
      requests-cache
    ];
    pythonImportsCheck = [ "fear_and_greed" ];
  };

  pythonAnalysis = pkgs.python3.withPackages (p: [
    p.yfinance
    p.pandas
    p.feedparser
    fear-and-greed
  ]);

  # Portfolios nach XDG statt ~/.clawdbot; ein gesetzter Wert gewinnt.
  zustand = ''export CLAWDBOT_STATE_DIR="''${CLAWDBOT_STATE_DIR:-$HOME/.local/share/stock-analysis}"'';

  stockAnalysis = pkgs.stdenvNoCC.mkDerivation {
    pname = "stock-analysis";
    version = "5.0-unstable-2026-03-06";
    src = quelleAnalysis;
    sourceRoot = "source/skills/stock-analysis";
    nativeBuildInputs = [ pkgs.makeWrapper ];
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin $out/share/stock-analysis $out/skill
      # Beide Dateien in EIN Verzeichnis: analyze_stock.py importiert
      # `portfolio` aus dem eigenen Ordner.
      cp scripts/analyze_stock.py scripts/portfolio.py $out/share/stock-analysis/
      makeWrapper ${pythonAnalysis}/bin/python3 $out/bin/stock-analysis \
        --add-flags $out/share/stock-analysis/analyze_stock.py \
        --run ${lib.escapeShellArg zustand}
      makeWrapper ${pythonAnalysis}/bin/python3 $out/bin/stock-portfolio \
        --add-flags $out/share/stock-analysis/portfolio.py \
        --run ${lib.escapeShellArg zustand}
      cp SKILL.md $out/skill/
      substituteInPlace $out/skill/SKILL.md \
        --replace-fail 'metadata: {"clawdbot":{"emoji":"📈","requires":{"bins":["uv"],"env":[]},"install":[{"id":"uv-brew","kind":"brew","formula":"uv","bins":["uv"],"label":"Install uv (brew)"}]}}' "" \
        --replace-fail 'uv run {baseDir}/scripts/analyze_stock.py' 'stock-analysis' \
        --replace-fail 'uv run {baseDir}/scripts/portfolio.py' 'stock-portfolio' \
        --replace-fail '~/.clawdbot/skills/stock-analysis/portfolios.json' '~/.local/share/stock-analysis/skills/stock-analysis/portfolios.json' \
        --replace-fail '- **Insider Activity**: Net buying/selling from SEC Form 4 filings (90-day window)' '- **Insider Activity**: NOT available in this installation (edgartools is not packaged); the weights renormalize without it'
      runHook postInstall
    '';
  };
in
{
  home-manager.users.${id.username} = {
    home.packages = [
      stockAnalyzer
      stockAnalysis
    ];
    home.file.".claude/skills/stock-analyzer".source = "${stockAnalyzer}/skill";
    home.file.".claude/skills/stock-analysis".source = "${stockAnalysis}/skill";
  };
}
