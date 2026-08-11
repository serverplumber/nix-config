{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

# Anthropic's official CLI for the Claude Developer Platform (`ant`) — not to
# be confused with pkgs.ant, which is Apache Ant, a Java build tool. Not in
# nixpkgs under any name, so packaged here directly from upstream.
#
# Version/commit pinned explicitly (resolved from the v1.22.1 git tag), not
# "whatever is newest on GitHub" — reproducible builds want a pin either way.
buildGoModule (finalAttrs: {
  pname = "ant";
  version = "1.22.1";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "anthropic-cli";
    rev = "c02335ad43818146937b8bdcc831f03d0794f1ec";
    hash = "sha256-jYSC6y5z67+duk8lkg5BsfG867LgsUy6IYtsfTS3AVA=";
  };

  vendorHash = "sha256-n64faF1uWdqDJalNsWxW1/IjlR/LOJyO/WhtHdzAFBE=";

  subPackages = [ "cmd/ant" ];

  ldflags = [
    "-s"
    "-w"
    "-X main.version=${finalAttrs.version}"
    "-X main.commit=${finalAttrs.src.rev}"
  ];

  doCheck = false;

  meta = {
    description = "CLI for the Claude Developer Platform — messages, agents, sessions, files, from the terminal";
    homepage = "https://github.com/anthropics/anthropic-cli";
    license = lib.licenses.mit;
    mainProgram = "ant";
    platforms = lib.platforms.unix;
  };
})
