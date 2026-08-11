#
# /etc/nixos/nginx-anycast.nix  —  TEMPORARY anycast smoke-test (super-a/b/d, identical)
#
# Serves a static "hello from anycast" page on the PUBLIC ANYCAST IP 160.72.197.238 ONLY,
# with an 80 -> 443 redirect. The self-signed cert is embedded below so EVERY node presents
# the SAME cert (under anycast you can't predict which node answers — a per-node cert would
# look inconsistent). Read-only by construction: the docroot is a nix-store dir, access
# logging is off, and there are no upload/write locations.
#
# THROWAWAY: this is an untrusted self-signed cert and its key is world-readable in the nix
# store / git. Fine for a quick reachability test; regenerate or delete before anything real.
# To TEAR DOWN: remove the `./nginx-anycast.nix` import (and the Makefile sync entry) + rebuild.
#
{ config, pkgs, lib, ... }:

let
  anycastIp = "160.72.197.238";

  # Static content — a read-only nix-store directory (no writable docroot).
  webroot = pkgs.writeTextDir "index.html" ''
    <!doctype html>
    <html lang="en">
    <head><meta charset="utf-8"><title>anycast</title></head>
    <body style="font-family: sans-serif; margin: 4rem;">
      <h1>hello from anycast</h1>
      <p>served on 160.72.197.238</p>
    </body>
    </html>
  '';

  # --- THROWAWAY self-signed cert (CN=anycast-test, SAN IP:160.72.197.238) ---
  cert = pkgs.writeText "anycast-test.crt" ''
    -----BEGIN CERTIFICATE-----
    MIIDIDCCAgigAwIBAgIUBsWHg0E7BF0Cy3gUMhLxfa+He5cwDQYJKoZIhvcNAQEL
    BQAwFzEVMBMGA1UEAwwMYW55Y2FzdC10ZXN0MB4XDTI2MDgxMTAzMzIyOFoXDTI3
    MDgxMTAzMzIyOFowFzEVMBMGA1UEAwwMYW55Y2FzdC10ZXN0MIIBIjANBgkqhkiG
    9w0BAQEFAAOCAQ8AMIIBCgKCAQEAn71PXBvAfT/aIt2KkH6E6XuPyUfduB71+6rt
    LamWyIpxB9HdhuU4pH3vSpgc2q0Ah+MloBXFnHXds1/Egfd529ZbMNxdSu8TD7te
    EWgBJIfXk5U7jRaBRLZcGIw85fPZadnwXTYgo5WP4WalxIeEcUSXUPYUKKJENirg
    4Ee/Zbzeh8hPfCNcgNojczYk2kmepvsm2liwjtwdXyJYR4yzkB4dHDzQGn7GtnOW
    rJdtdIUW2Ao6FBeTwjKablpYs3dkyGjtDu9Bfvxq3JhjjmpMT0y0fqVtk3mJMCoD
    cCNoOGaBH5wt/bAHwzFlUIKwH2fYeyJDn3wYK1EWJkz5JLl9YQIDAQABo2QwYjAd
    BgNVHQ4EFgQURvYCyYX0VFWgbY4qYZHMXrsv9eYwHwYDVR0jBBgwFoAURvYCyYX0
    VFWgbY4qYZHMXrsv9eYwDwYDVR0TAQH/BAUwAwEB/zAPBgNVHREECDAGhwSgSMXu
    MA0GCSqGSIb3DQEBCwUAA4IBAQAHTwwqSrH13T1rFB2leYWPgZVuooB5k+4nF3mS
    sRfnb62NN873zmsvrROzeFyvaTjB0FF9C+VERB0PbFU6OsH6yxAsBkyNxeb2br3g
    FmU2nhvcnKiixveaKP8J0OFB0LqdBZI3KdNB0aEXmCpZBNtUYFGwm+FScLmqS4Kg
    ClrDaTgdCQxnYYK9ebr9qQKNO33DvW1DyXpza4Lm5HZLfbO2DJAitbRYpAnRLfyw
    hfIrl3/Btn+DVaal59EfuF2r5SBgoTnNao915cbwZJSSihXwmsgGKwKZvI2QDVY3
    Gg+vhgIm0T19eX8pTeVP5g9AF6DtyVmCb9WzFHFmJr6wLSIw
    -----END CERTIFICATE-----
  '';
  key = pkgs.writeText "anycast-test.key" ''
    -----BEGIN PRIVATE KEY-----
    MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQCfvU9cG8B9P9oi
    3YqQfoTpe4/JR924HvX7qu0tqZbIinEH0d2G5Tikfe9KmBzarQCH4yWgFcWcdd2z
    X8SB93nb1lsw3F1K7xMPu14RaAEkh9eTlTuNFoFEtlwYjDzl89lp2fBdNiCjlY/h
    ZqXEh4RxRJdQ9hQookQ2KuDgR79lvN6HyE98I1yA2iNzNiTaSZ6m+ybaWLCO3B1f
    IlhHjLOQHh0cPNAafsa2c5asl210hRbYCjoUF5PCMppuWlizd2TIaO0O70F+/Grc
    mGOOakxPTLR+pW2TeYkwKgNwI2g4ZoEfnC39sAfDMWVQgrAfZ9h7IkOffBgrURYm
    TPkkuX1hAgMBAAECggEAE9/f8dvaFTtOjqv1w4iaTNp8x1RTt8bSYB+iJt5Ezmq7
    KXfpEhGO/JhWn3dRj7uap02RrttGnPLlRJ4Tuv/pf3qqGegxC1O3kWuEhrHkAoGM
    RuZ4ZFN6fewahUtdgFbYpBzjlRVY9kFzh13YHh2mUtlv4jjbxTp7NioblIwYujWV
    OzliCTt2w0/cp9rnNtkK4+Nk8rdNaQXKuNDAtpzFPZeqj8HLdyQc9XoxP2qYYoPL
    4efmkH1KhGLXw0A6KtF408hhzdTCFuHi4NrAD7uNBfnva7gJ1iXwC9BHkwLaEEp1
    MzvVX+LHd8fFu3UfHZ7UzhJ7CdL62q+oXs0CCmmV4QKBgQDP80WJqumHtF1SBrkU
    ldeSd4+kh9TfwvOFctalLIONJW+HBn2q5cp48vU0XhCPDhFqm+1uyE8SPWXZeYrf
    iB9+jfgHaodipg3bohQb2KksqxWR2Z4cAa7wwGGnIK07/o4LeSjxIrCU0Ec564ye
    jW6A4lAQJQfc2Mtz2XKbh3KrxQKBgQDEpkLv7lBfmx0wHzTR7GdxsIKG9yVPj9el
    1/fDMzoBnBH64g7qJxeCxbfQtMGFpCuDXfa6VIQIJ0LL8Rsnsjr2s/eI1Hx38ZwP
    LIajLoOgkRjDZrGfXK1UIKfKiAXuVzcqL017Jzi8JVwmpXvb3EH6cvr7BPiTDV9s
    eUQUav4Y7QKBgQClwjTb1/Duy0bX66P8VLTRe5x0ehGli7Cx3yhZ4XG7QOv1pabm
    YuVSI9hxNcndPkmDwWcxt1nQIEDfaZLZO5hfOKtMvg3NBLBnMnr0929iu70l1WHC
    0VSxc6hjoBh2iiKP4rRQAmbfOGaONMSSXgqHkd5gACSUVftXDS3d68nsQQKBgHFj
    oQMx+hw2l6zwwYct9jPC4HCsP1JSEblp/04J0q+s610rTghMBC1+jlAEefXyRLjZ
    zHOCWiNNaCGqY8sO5RrtiJTYWPDcWu0Q8o1TO8ixAYNiSpcmXDc/ISESL8FPftqP
    LfEOG5O5QxpxnyqWJWEhPYDSS/aW5mfowI25Z8y9AoGBAKMWX+DEDLUB1wu1yF8y
    AG9s+55STll4fYS7P3HnzJvSkHxybU//mPrVBVAx6KxMz+UHPlofjLmZnE4WTohn
    LVQBdlZfxMd6YOdNxW4liCLIEm7kMFXbL+mxRVQIuZ3jvnvvzwKQpX4OvIFd38zU
    JoHj8LzObul3lumUfhffDFYR
    -----END PRIVATE KEY-----
  '';
in
{
  services.nginx = {
    enable = true;
    recommendedTlsSettings = true;
    recommendedOptimisation = true;

    # Bind to the anycast IP ONLY (not the node's other IPs). forceSSL adds the 80->443
    # redirect + serves on 443; `default` makes it answer IP access with no Host match.
    virtualHosts."anycast" = {
      default = true;
      listenAddresses = [ anycastIp ];
      forceSSL = true;
      sslCertificate = "${cert}";
      sslCertificateKey = "${key}";
      root = "${webroot}";
      extraConfig = "access_log off;";   # read-only test: no request log write path
    };
  };

  # nginx must start AFTER the anycast IP is on dummy1 (service-loopbacks), or the bind fails.
  systemd.services.nginx.after = [ "service-loopbacks.service" ];
}
