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
#   1. Bump `version` below to whatever `dpkg-deb -I <new .deb>` reports for `Version:`.
#   2. Compute the new SRI hash:
#        nix-prefetch-url --type sha256 \
#          https://downloads.nordlayer.com/linux/latest/debian/latest/nordlayer_latest_amd64.deb
#        nix hash convert --to sri --hash-algo sha256 <output-from-above>
#      (Or set `hash = lib.fakeHash;`, run `nix build`, copy the expected hash from the
#      error message.)
#   3. Paste the resulting `sha256-...` into the `hash` attribute below.
#
# Why no versioned URL: NordLayer does not publish public versioned download URLs
# (the apt-pool paths return 403 via Cloudflare). `latest` is the only public URL,
# so the SRI `hash` IS our integrity check — Nix refuses to use the file if its
# sha256 doesn't match, which means any silent re-publish by upstream will surface
# as a build failure rather than a silent binary swap.

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
  version = "3.5.0";

  src = fetchurl {
    url = "https://downloads.nordlayer.com/linux/latest/debian/latest/nordlayer_latest_amd64.deb";
    # sha256 of the .deb at the URL above. See header for update procedure.
    hash = "sha256-de0NTrtBVNo+rHqB1AUdfDHVoA+2r9RnbncHPlNLo+U=";
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
