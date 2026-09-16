# BYOID (External Account) Live Integration Testing Guide

This guide explains how to configure and execute live integration tests for the **Bring Your Own Identity (BYOID) / External Account Credentials** implementation in `GoogleAuth` (`packages/swift-google-auth`).

______________________________________________________________________

## 1. Overview & Architecture

Google Cloud Workload and Workforce Identity Federation allows applications to authenticate to Google Cloud APIs using external identity providers (OIDC, SAML, AWS, Apple ID) without long-lived service account keys ([AIP-4117](https://google.aip.dev/auth/4117)).

In the programmatic external account flow, the SDK delegates third-party identity token retrieval to a `SubjectTokenProvider` callback, then exchanges that token with Google's Security Token Service (STS) at `https://sts.googleapis.com/v1/token` for a short-lived Google Cloud access token (`Bearer ya29...`).

Following the architecture in `google-cloud-rust`, the Swift integration tests obtain test OIDC identity tokens directly via the **IAM Credentials `generateIdToken` REST API** using ambient Application Default Credentials (ADC), or via an injected `EXTERNAL_ACCOUNT_SUBJECT_TOKEN` environment variable.

```text
┌───────────────────────────────────────────────────────────┐
│                 Swift Integration Test                    │
└─────────────┬───────────────────────────────┬─────────────┘
              │ 1. IAM generateIdToken REST   │ 2. SubjectTokenProvider
              │    (authenticated via ADC)    │
              ▼                               ▼
┌───────────────────────────┐   ┌───────────────────────────┐
│ Google IAM Credentials    │   │ GoogleAuth           │
│ (iamcredentials.googleapis)   │ (ExternalAccountCreds)    │
└─────────────┬─────────────┘   └─────────────┬─────────────┘
              │ Returns raw ID token (JWT)    │ 3. POST /v1/token
              └──────────────────────────────►│    grant_type=token-exchange
                                              ▼
                                ┌───────────────────────────┐
                                │ Google STS                │
                                │ (sts.googleapis.com)      │
                                └─────────────┬─────────────┘
                                              │ Returns TokenResponse
                                              ▼
                                ┌───────────────────────────┐
                                │ Access Token              │
                                │ (Bearer ya29...)          │
                                └───────────────────────────┘
```

______________________________________________________________________

## 2. Test Environment

Tests run against the pre-provisioned test project:

- **Project ID**: `rust-external-account-joonix`
- **Project Number**: `1092239828259`
- **Workload Identity Pool**: `google-idp`
- **Workload Identity Provider**: `google-idp` (trusts issuer `https://accounts.google.com`)
- **Audience URI**: `//iam.googleapis.com/projects/1092239828259/locations/global/workloadIdentityPools/google-idp/providers/google-idp`
- **Service Account**: `testsa@rust-external-account-joonix.iam.gserviceaccount.com`

______________________________________________________________________

## 3. Prerequisites & One-Time Setup

### 3.1 Verify Access to the Test Project

Ensure your local `gcloud` CLI is authenticated and has access to the test project:

```bash
gcloud projects describe rust-external-account-joonix
```

Verify that the workload identity pool and provider exist:

```bash
gcloud iam workload-identity-pools describe google-idp \
    --project="rust-external-account-joonix" \
    --location="global"

gcloud iam workload-identity-pools providers describe google-idp \
    --project="rust-external-account-joonix" \
    --workload-identity-pool="google-idp" \
    --location="global"
```

### 3.2 Grant Token Creator Permission

To allow your user account to generate OIDC ID tokens via service account impersonation, bind the `roles/iam.serviceAccountTokenCreator` role on `testsa`:

```bash
USER_EMAIL=$(gcloud config get-value account)

gcloud iam service-accounts add-iam-policy-binding \
    testsa@rust-external-account-joonix.iam.gserviceaccount.com \
    --project="rust-external-account-joonix" \
    --role="roles/iam.serviceAccountTokenCreator" \
    --member="user:${USER_EMAIL}"
```

### 3.3 Ensure Application Default Credentials (ADC) are Configured

For the test to dynamically call the IAM Credentials API, ensure local ADC is active:

```bash
gcloud auth application-default login
```

______________________________________________________________________

## 4. Running the Integration Tests

### 4.1 Required Environment Variables

The integration tests check for the presence of the following environment variables. If they are not set, the tests are safely skipped:

| Variable | Description | Example Value |
| :--- | :--- | :--- |
| `GOOGLE_CLOUD_PROJECT` | GCP Project ID | `rust-external-account-joonix` |
| `GOOGLE_WORKLOAD_IDENTITY_OIDC_AUDIENCE` | Full Identity Provider Audience URI | `//iam.googleapis.com/projects/1092239828259/locations/global/workloadIdentityPools/google-idp/providers/google-idp` |
| `EXTERNAL_ACCOUNT_SERVICE_ACCOUNT_EMAIL` | Service Account to generate ID token for via IAM API | `testsa@rust-external-account-joonix.iam.gserviceaccount.com` |
| `EXTERNAL_ACCOUNT_SUBJECT_TOKEN` | *(Optional)* Direct subject token override (e.g. Apple ID JWT) | `eyJhbGci...` |

### 4.2 Execute the Test

Before running root tests, link local package dependencies using `ci/package-dependencies.sh`:

```bash
source ci/package-dependencies.sh
edit_package_dependencies .
```

#### Run Google OIDC Test:
```bash
GOOGLE_CLOUD_PROJECT="rust-external-account-joonix" \
GOOGLE_WORKLOAD_IDENTITY_OIDC_AUDIENCE="//iam.googleapis.com/projects/1092239828259/locations/global/workloadIdentityPools/google-idp/providers/google-idp" \
EXTERNAL_ACCOUNT_SERVICE_ACCOUNT_EMAIL="testsa@rust-external-account-joonix.iam.gserviceaccount.com" \
swift test -q --filter ExternalAccountIntegrationTests/testGoogleOIDCWorkloadIdentityFederation
```

#### Run Apple ID Test:
```bash
GOOGLE_CLOUD_PROJECT="rust-external-account-joonix" \
APPLE_WORKLOAD_IDENTITY_OIDC_AUDIENCE="//iam.googleapis.com/projects/1092239828259/locations/global/workloadIdentityPools/google-idp/providers/apple-idp" \
APPLE_ID_TOKEN="<PASTE_FRESH_APPLE_ID_TOKEN>" \
swift test -q --filter ExternalAccountIntegrationTests/testAppleIDWorkloadIdentityFederation
```

When finished, restore the root package manifest:
```bash
restore_package_dependencies .
```

### 4.3 Expected Output

```text
◇ Suite "External Account (BYOID) Integration Tests" started.
◇ Test "Exchanges Google OIDC token via STS and verifies access token" started.
✔ Test "Exchanges Google OIDC token via STS and verifies access token" passed after 0.558 seconds.
✔ Suite "External Account (BYOID) Integration Tests" passed after 0.560 seconds.
✔ Test run with 1 test in 1 suite passed after 0.560 seconds.
```

______________________________________________________________________

## 5. What the Integration Test Validates

The test (`Tests/Auth/ExternalAccountIntegrationTests.swift`):

1. Invokes the IAM Credentials client (`GoogleIAMCredentialsV1.IAMCredentialsClient().generateIdToken(...)`) via ambient ADC (or uses `EXTERNAL_ACCOUNT_SUBJECT_TOKEN`) to obtain a fresh OIDC ID token (JWT).
1. Instantiates `ExternalAccountCredentials` using the programmatic credential source and the returned subject token.
1. Invokes `creds.headers()` to trigger a live HTTP POST exchange with Google STS (`https://sts.googleapis.com/v1/token`).
1. Asserts that the response headers contain an `Authorization` header with a valid Google Cloud access token starting with `Bearer ya29.`.
1. Also instantiates the top-level public `Credentials(configuration: .programmaticExternalAccount(config))` entry point and verifies that public API resolution succeeds.

______________________________________________________________________

## 6. Troubleshooting & Common Pitfalls

| Error / Symptom | Root Cause | Solution |
| :--- | :--- | :--- |
| `PERMISSION_DENIED: Failed to impersonate testsa` | Missing `roles/iam.serviceAccountTokenCreator` binding on `testsa`. | Re-run Section 3.2 to grant the role to your authenticated gcloud user account. |
| STS HTTP 400: `Invalid value for "audience"` | Audience resource name misspelling (e.g., using `workloadPools` instead of `workloadIdentityPools`). | Workload Identity Federation uses `//iam.googleapis.com/projects/<NUM>/locations/global/workloadIdentityPools/<POOL>/providers/<PROV>`. Ensure `workloadIdentityPools` is used. |
| STS HTTP 400: `Scope(s) must be provided` | Scopes parameter omitted during token exchange. | In `GoogleAuth`, scopes default to `["https://www.googleapis.com/auth/cloud-platform"]` per AIP-4117. Ensure non-empty scopes are provided if overriding. |
| Test skipped with message `Skipping M1 test: Missing ...` | Required environment variables were not set in the shell running `swift test`. | Export `GOOGLE_CLOUD_PROJECT`, `GOOGLE_WORKLOAD_IDENTITY_OIDC_AUDIENCE`, and `EXTERNAL_ACCOUNT_SERVICE_ACCOUNT_EMAIL` prior to executing the test. |
