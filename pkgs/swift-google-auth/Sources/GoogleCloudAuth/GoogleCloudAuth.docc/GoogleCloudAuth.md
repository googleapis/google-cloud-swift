# ``GoogleCloudAuth``

[authentication]: https://cloud.google.com/docs/authentication
[credentials]: https://cloud.google.com/docs/authentication#credentials
[principals]: https://cloud.google.com/iam/docs/overview#principals
[tokens]: https://cloud.google.com/docs/authentication#token
[API Keys]: https://cloud.google.com/docs/authentication/api-keys-use
[Application Default Credentials]: https://cloud.google.com/docs/authentication/application-default-credentials
[Set up ADC]: https://cloud.google.com/docs/authentication/provide-credentials-adc
[Service Accounts]: https://cloud.google.com/iam/docs/service-account-overview
[Workload Identity Federation]: https://cloud.google.com/iam/docs/workload-identity-federation
[Workforce Identity Federation]: https://cloud.google.com/iam/docs/workforce-identity-federation
[Metadata Server]: https://cloud.google.com/compute/docs/metadata/overview
[Universe Domains]: https://docs.cloud.google.com/docs/overview#universes_regions_and_zones
[Quota Projects]: https://cloud.google.com/docs/quotas/quota-project
[AIP-4111]: https://google.aip.dev/auth/4111
[AIP-4117]: https://google.aip.dev/auth/4117

This package provides types to authenticate calls into Google Cloud APIs.

## Overview

Almost all calls into Google Cloud require [authentication]: verifying that the
caller is who they claim to be. Once received, the destination service verifies that the
caller is authorized to perform the specific requested operation.

### Principals, Credentials, and Tokens

Google Cloud manages access through several key concepts:

- **[Principals]**: An identity that can be granted access to Google Cloud resources.
  Principals can be human users (managed via Google Accounts or Cloud Identity),
  [Service Accounts] (identities for workloads, microservices, or compute resources),
  or external federated identities from third-party identity providers.
- **[Credentials]**: A digital object providing proof of identity, such as a
  service account's RSA private key, an authorized user's OAuth 2.0 refresh token,
  or an external identity provider assertion.
- **[Tokens]**: Short-lived, digitally signed access tokens asserting that the caller
  possesses valid credentials.

Modern authentication protocols avoid sending long-lived credentials directly over
the wire. Sending raw credentials increases the risk of accidental exposure through
application logs or transport errors. Because credentials are often long-lived, that
exposure risk is extended over time.

Instead, the authentication library exchanges credentials for time-limited access
tokens (or generates local self-signed JSON Web Signatures under [AIP-4111]). Tokens
are automatically refreshed before they expire and may be restricted by OAuth 2.0
scopes or target audience URIs.

### Application Default Credentials (ADC)

The primary entry point is the ``Credentials`` struct. A default-initialized
`Credentials` instance automatically resolves authentication using
[Application Default Credentials] (ADC), following the standard precedence order:

1. **Environment Variable**: The path pointed to by `GOOGLE_APPLICATION_CREDENTIALS`.
   This file can contain a service account key or authorized user credentials.
2. **Well-Known User Credentials**: The user credentials file created by running
   `gcloud auth application-default login` on a developer workstation.
3. **[Metadata Server] (MDS)**: The link-local metadata service
   (`http://metadata.google.internal`) automatically available in Google Cloud
   runtime environments (Google Compute Engine, Google Kubernetes Engine, Cloud Run).
   MDS issues short-lived access tokens for the runtime's attached service account
   without requiring private keys on the host.

If you are developing locally, you can [Set up ADC] using the `gcloud` CLI.

### Quota Projects and Universe Domains

Requests into Google Cloud can also specify contextual routing and billing settings:

- **[Quota Projects]**: In certain configurations, you may authenticate using credentials
  from one project while attributing API usage, billing, and quota limits to a different
  project via the `x-goog-user-project` HTTP header. This requires the
  `serviceusage.services.use` permission on the quota project.
- **[Universe Domains]**: A universe domain identifies the root domain of the target
  cloud environment. The default universe domain is `googleapis.com`. Sovereign or
  air-gapped environments can specify custom universe domains.

### Programmatic and Federated Credentials

For advanced scenarios, ``CredentialsConfiguration`` allows explicit configuration:

- **Service Account Keys**: Sign local JWT assertions in memory using raw RSA private keys.
- **User Accounts**: Manage OAuth 2.0 refresh token exchanges for authorized users.
- **[Workload Identity Federation]**: Authenticate workloads running outside Google Cloud
  (AWS, Azure, Apple Account, GitHub Actions, Okta) by exchanging external subject tokens for
  Google Cloud access tokens via the Security Token Service ([AIP-4117]).
- **[API Keys]**: Associate requests with a Google Cloud project for billing and quota
  when accessing APIs that support API key authentication.
