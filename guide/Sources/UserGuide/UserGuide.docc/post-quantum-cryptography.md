# Post-quantum cryptography

[Post-quantum cryptography]: https://cloud.google.com/security/resources/post-quantum-cryptography

In this guide, you learn about the Google Cloud client libraries for Swift
support for Post-quantum cryptography (PQC). PQC protects encrypted
communications against potential future quantum computing capabilities that
could compromise classical public-key cryptography.

## Summary

Google Cloud services and Google Front End load balancers support hybrid
post-quantum key agreement (`X25519MLKEM768` IANA group ID `0x11ec` / 4588)
during TLS 1.3 handshakes.

The Google Cloud Client Libraries for Swift enable and negotiate post-quantum
hybrid key agreement by default without requiring custom configuration.

## How PQC operates in the Swift client libraries

The Swift client libraries either gRPC or `AsyncHTTPClient`, both backed by
`swift-nio-ssl` and embedded BoringSSL (`CNIOBoringSSL`).

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

## Next Steps

* Google's [Post-quantum cryptography] guide contains more information about
  this topic.
