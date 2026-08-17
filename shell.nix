{ pkgs ? import <nixpkgs> {} }:
  pkgs.mkShell {
  buildInputs = [
	pkgs.nodejs
	pkgs.jq
	pkgs.mkdocs
  ];
    shellHook = ''
    npm set prefix $PWD/.npm-global
    export PATH=$PWD/.npm-global/bin:$PATH
    export NODE_PATH=$PWD/.npm-global/lib/node_modules
    GIT_AUTHOR_EMAIL='florian-marie@getvirtualbrain.com'
  '';
}
