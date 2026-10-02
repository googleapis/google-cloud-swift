# Post-quantum cryptography

Post-quantum cryptography (PQC) protects encrypted communications against
potential future quantum computing capabilities that could compromise classical
public-key cryptography.

Google Cloud services and Google Front End load balancers support hybrid
post-quantum key agreement (`X25519MLKEM768`, IANA group ID `0x11ec` / 4588)
during TLS 1.3 handshakes.

The Google Cloud Client Libraries for Swift enable and negotiate post-quantum
hybrid key agreement by default without requiring custom configuration.

## How PQC operates in Swift

The Swift client libraries use `AsyncHTTPClient` backed by `swift-nio-ssl` and
embedded BoringSSL (`CNIOBoringSSL`).

When negotiating TLS 1.3 connections, `swift-nio-ssl` configures
`X25519MLKEM768` as the first and preferred key exchange group in its default
curve list:

- `X25519MLKEM768` (hybrid post-quantum key exchange)
- `X25519` (classical curve)
- `secp256r1` (classical curve P-256)
- `secp384r1` (classical curve P-384)

During the TLS 1.3 `ClientHello`, the client offers `X25519MLKEM768`. Because
Google Cloud endpoints support this group, the handshake selects it, securing
data in transit against retrospective decryption attacks.

If a server or intermediate network proxy does not support `X25519MLKEM768`,
negotiation automatically and transparently falls back to classical algorithms.

## Custom root certificates

In development, staging, or VPC Service Controls (VPC-SC) environments with
custom proxies or self-signed test servers (such as `gapic-showcase`), you can
configure trusted root CA certificates in memory via `ClientOptions`:

```swift
let options = try ClientOptions().with {
  $0.endpoint = "https://my-internal-proxy.local:8443"
  $0.rootCertificates = myCustomRootCertificatesPEM
}
let client = try SecretManagerServiceClient(options)
```

## Verifying PQC negotiation

You can verify that PQC key exchange is active by:

1. **Showcase Integration Testing**: Spawning `gapic-showcase` with
   `--tls --tls-groups 0x11ec` strictly requires clients to negotiate
   `X25519MLKEM768`. Handshakes fail if PQC is not supported.
2. **Server-Side Headers**: Testing servers like `gapic-showcase` return the
   negotiated key agreement group in the `x-showcase-tls-group` response header.
3. **Packet Capture & Network Inspection**: Inspecting the TLS 1.3 `ClientHello`
   and `ServerHello` packets using network analyzers (such as Wireshark or `tcpdump`)
   confirms group `0x11ec` (`X25519MLKEM768`) in the `supported_groups` and
   `key_share` extensions.
