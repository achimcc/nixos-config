{ lib
, buildFHSEnv
, fetchFromGitHub
, writeShellScript
}:

let
  shadowSrc = fetchFromGitHub {
    owner = "shadow";
    repo = "shadow";
    rev = "v3.3.0";
    sha256 = "0jlgal60xvd911gvfmfyrd2w68gixvl9dgidbd79wl2ngapay1cj";
  };
in
buildFHSEnv {
  name = "shadow";

  targetPkgs = pkgs: with pkgs; [
    # Build dependencies
    cmake
    gnumake
    gcc
    glib
    glib.dev
    pkg-config
    python3
    python3.pkgs.networkx
    rustup
    clang
    libclang.lib
    xz
    util-linux
    git
    findutils
    binutils
    
    # Runtime dependencies
    bash
    coreutils
    which
  ];

  runScript = writeShellScript "shadow-wrapper" ''
    SHADOW_DIR="$HOME/.local/share/shadow"
    SHADOW_BUILD="$SHADOW_DIR/build"
    SHADOW_INSTALL="$HOME/.local"
    
    # Setup Rust via rustup (nur beim ersten Mal)
    if [ ! -d "$HOME/.rustup" ]; then
      echo "Installiere Rust Toolchain..."
      rustup-init -y --default-toolchain stable --profile minimal
    fi
    
    export PATH="$HOME/.cargo/bin:$PATH"
    
    # Shadow nur beim ersten Mal bauen
    if [ ! -f "$SHADOW_INSTALL/bin/shadow" ]; then
      echo "Baue Shadow Simulator (kann einige Minuten dauern)..."
      mkdir -p "$SHADOW_DIR"
      cd "$SHADOW_DIR"
      
      if [ ! -d "shadow" ]; then
        cp -r ${shadowSrc} shadow
        chmod -R u+w shadow
      fi
      
      cd shadow
      
      # Build mit korrekter Syntax (setup build hat keine --prefix Option)
      ./setup build --clean
      ./setup install
    fi
    
    # Shadow ausführen
    exec "$SHADOW_INSTALL/bin/shadow" "$@"
  '';

  meta = with lib; {
    description = "Discrete-event network simulator that runs real applications";
    longDescription = ''
      Shadow is a discrete-event network simulator that directly executes real
      application code, enabling you to simulate distributed systems with thousands of
      network-connected processes in realistic and scalable private network experiments.
    '';
    homepage = "https://shadow.github.io";
    license = licenses.gpl3Plus;
    maintainers = [ ];
    platforms = platforms.linux;
    mainProgram = "shadow";
  };
}
