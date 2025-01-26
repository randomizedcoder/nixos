# https://nixos.org/manual/nixpkgs/stable/#sec-language-go
{
  xtcp2 = buildGoModule rec {
    pname = "xtcp2";
    version = "2.0.0";

    src = fetchFromGitHub {
      owner = "randomizedcoder";
      repo = "xtcp2";
      rev = "v${version}";
      hash = "sha256-qoAp8yAc4lJmlnHHcZskRzkleZ3Q5Gu3Lhk9u1jMR4g=";
    };

    vendorHash = "sha256-/5nH7zHg8zxWFgtVzSnfp7RZGvPWiuGSEyhx9fE2Pvo=";

    subPackages = [
      "cmd/xtcp2"
    ];

    #excludedPackages = [ "bench" ];

    #ldflags = [ "-s" "-w" ];

    meta = with lib; {
      homepage = "https://xtcp.io/";
      description = "xtcp2";
      changelog = "https://github.com/randomizedcoder/xtcp2/ChangeLog.md";
      license = licenses.mit;
    };
  };
}