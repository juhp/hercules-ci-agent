{ pkgs
, haskellPackages
}:
let inherit (pkgs) lib;
in
haskellPackages.shellFor {
  # Just in case
  NIX_PATH = "nixpkgs=${pkgs.path}";

  packages = p: [
    p.hercules-ci-api-core
    p.hercules-ci-api
    p.hercules-ci-api-agent
    p.hercules-ci-agent
    p.hercules-ci-agent_lib
    p.hercules-ci-agent-test
    p.hercules-ci-cli
    p.hercules-ci-cnix-expr

    # Disable so that cachix, its consumer becomes a regular dependency, in order
    # not to confuse the stack repl + hie-bios + hls setup.
    # p.hercules-ci-cnix-store
    # p.cachix

    # TODO: https://github.com/NixOS/nixpkgs/pull/164305
    { getCabalDeps.libraryHaskellDepends = [ haskellPackages.releaser ]; outPath = "/nix/store/shellFor-cabal-dummy-out-path"; }
  ];
  buildInputs = [
    pkgs.boost
    pkgs.nlohmann_json # FIXME remove
    pkgs.nix
  ];
  nativeBuildInputs = [
    pkgs.cabal-install
    # pkgs.jq
  ];
  shellHook = ''
    LD_LIBRARY_PATH=${lib.getLib pkgs.boost}/lib:$LD_LIBRARY_PATH
  '';
}
