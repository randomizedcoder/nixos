# nordlayer-package.nix
#
# Repackages the official NordLayer Linux client (Go-based daemon + CLI)
# from the Debian package they publish at downloads.nordlayer.com.
#
# Output layout:
#   $out/bin/nordlayer            — CLI (talks to daemon over /run/nordlayer/nordlayer.sock)
#   $out/bin/nordlayer-diagtool   — diagnostic tool
#   $out/sbin/nordlayerd          — daemon
#   $out/libexec/nordlayer/       — helper binaries (nordlayer-openvpn, nordlayer-resolvconf)
#   $out/etc/nordlayer/           — config templates, CA certs
#   $out/share/                   — polkit rules, desktop entries, completions, man pages
#
# Updating:
#   1. Fetch the apt Packages index (the source of truth for version + hash):
#        https://downloads.nordlayer.com/linux/latest/debian/dists/stable/main/binary-amd64/Packages
#   2. In the `nordlayer` stanza, read `Version:` and `SHA256:`. Bump `version` below to match;
#      the `url` tracks it automatically via `${version}`.
#   3. Convert the hex SHA256 to SRI and paste into `hash`:
#        nix hash convert --to sri --hash-algo sha256 <sha256-hex-from-Packages>
#      (Or set `hash = lib.fakeHash;`, run `nix build`, copy the expected hash from the
#      error message.)
#
# Why the versioned pool URL: NordLayer serves stable, versioned .debs at
# `.../debian/pool/main/nordlayer_<version>_amd64.deb` (reachable — the earlier belief that these
# 403'd via Cloudflare was wrong). We pin that instead of the moving `latest` URL so an upstream
# release can never silently swap our .deb mid-`nix build`; a new release is now a deliberate
# `version` + `hash` bump. The SRI `hash` remains the integrity check either way.

{ stdenv
, lib
, fetchurl
, dpkg
, autoPatchelfHook
, makeWrapper
, libcap_ng
}:

stdenv.mkDerivation rec {
  pname = "nordlayer";
  version = "3.5.1";

  src = fetchurl {
    url = "https://downloads.nordlayer.com/linux/latest/debian/pool/main/nordlayer_${version}_amd64.deb";
    # sha256 of the .deb at the URL above. See header for update procedure.
    hash = "sha256-qDWf5s7jRUcmfyEOdKlq7Lu2uOrmZVT4M7zoEq2D4O8=";
  };

  nativeBuildInputs = [ dpkg autoPatchelfHook makeWrapper ];

  # Daemon and CLI dynamically link only against glibc.
  # nordlayer-openvpn additionally needs libcap-ng.
  buildInputs = [ libcap_ng ];

  unpackPhase = ''
    dpkg-deb -x $src ./extract
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/sbin $out/libexec/nordlayer $out/etc $out/share

    # Main binaries
    install -Dm755 ./extract/usr/bin/nordlayer            $out/bin/nordlayer
    install -Dm755 ./extract/usr/bin/nordlayer-diagtool   $out/bin/nordlayer-diagtool
    install -Dm755 ./extract/usr/sbin/nordlayerd          $out/sbin/nordlayerd

    # Helper binaries — these are invoked by the daemon, likely via hardcoded
    # /usr/libexec/nordlayer/* paths. We stage them here; the NixOS module
    # symlinks them at /usr/libexec/nordlayer/ during activation.
    install -Dm755 ./extract/usr/libexec/nordlayer/nordlayer-openvpn     $out/libexec/nordlayer/nordlayer-openvpn
    install -Dm755 ./extract/usr/libexec/nordlayer/nordlayer-resolvconf  $out/libexec/nordlayer/nordlayer-resolvconf
    # nordlayer-setcap is a setcap helper used during the .deb postinst —
    # not needed at runtime on NixOS (we use security.wrappers instead).

    # Config templates and CA certs
    cp -r ./extract/etc/nordlayer $out/etc/nordlayer

    # Polkit rules + desktop integration
    mkdir -p $out/share/polkit-1/rules.d
    cp ./extract/usr/share/polkit-1/rules.d/90-com.nordlayer.VPN.rules $out/share/polkit-1/rules.d/

    if [ -d ./extract/usr/share/applications ]; then
      cp -r ./extract/usr/share/applications $out/share/
    fi
    if [ -d ./extract/usr/share/icons ]; then
      cp -r ./extract/usr/share/icons $out/share/
    fi

    # Shell completions
    mkdir -p $out/share/bash-completion/completions
    if [ -f ./extract/usr/share/bash-completion/completions/_nordlayer ]; then
      install -m644 ./extract/usr/share/bash-completion/completions/_nordlayer $out/share/bash-completion/completions/nordlayer
    fi
    if [ -f ./extract/usr/share/zsh/vendor-completions/_nordlayer ]; then
      install -Dm644 ./extract/usr/share/zsh/vendor-completions/_nordlayer $out/share/zsh/site-functions/_nordlayer
    fi
    if [ -f ./extract/usr/share/fish/vendor_completions.d/nordlayer.fish ]; then
      install -Dm644 ./extract/usr/share/fish/vendor_completions.d/nordlayer.fish $out/share/fish/vendor_completions.d/nordlayer.fish
    fi

    # Man page
    if [ -f ./extract/usr/share/man/man1/nordlayer.1.gz ]; then
      install -Dm644 ./extract/usr/share/man/man1/nordlayer.1.gz $out/share/man/man1/nordlayer.1.gz
    fi

    runHook postInstall
  '';

  # Don't strip — the binaries are already stripped, and stripping a Go binary
  # again is just a waste of build time.
  dontStrip = true;

  meta = with lib; {
    description = "NordLayer secure network access (repackaged from upstream .deb)";
    homepage = "https://nordlayer.com/";
    license = licenses.unfree; # Proprietary client
    platforms = [ "x86_64-linux" ];
    mainProgram = "nordlayer";
  };
}
