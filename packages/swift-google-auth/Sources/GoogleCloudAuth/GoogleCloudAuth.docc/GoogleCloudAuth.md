# ``GoogleCloudAuth``

[authentication]: https://docs.cloud.google.com/docs/authentication
[credentials]: https://docs.cloud.google.com/docs/authentication#credentials
[principal]: https://docs.cloud.google.com/docs/authentication#principal
[API Keys]: https://docs.cloud.google.com/docs/authentication/api-keys-use
[Application Default Credentials]: https://docs.cloud.google.com/docs/authentication/application-default-credentials
[Set up ADC]: https://docs.cloud.google.com/docs/authentication/provide-credentials-adc

This package provides types to authenticate calls into Google Cloud APIs.

## Overview

Almost all calls into Google Cloud require [authentication]: verifying that the
caller is who they claim to be. Once received, the service verifies that the
caller is also authorized to make the specific request.

The types in this library mainly concern themselves with the process of
obtaining and creating [credentials], a digital object that provide proof of
identity for authentication. Rarely, these credentials can encode restrictions
to limit their scope: the type of operations they may perform, or where the
request may originate from.

Note that the library does not perform authentication nor authorization: that
functionality always reside in the service.

The main type is ``Credentials``, this class generates a set of headers with the
authentication tokens or api keys that authenticate the request. The class
supports several different authentication methods, including [API keys] and
external accounts.

A default-initialized `Credentials` type uses [Application default credentials]
(ADC). The first time you use the client libraries you may need to [Set-up ADC]
in your development environment.

Some authentication methods create credentials that expire after some time. This
limits the impact of disclosing the credentials, as they naturally stop working
after some time. In this case the `Credentials` type automatically refreshes the
credentials before they expire.

Likewise, some authentication methods require contacting remove servers or
perform relatively heavy cryptographic computations to generate the credentials.
The `Credentials` type caches such credentials while they have not expired.

In most Google Cloud environments a default initialized `Credentials` can find
the right authentication method for that environment.

Some applications may wish to initialize the credentials from data obtained
programmatically. In that case, use ``CredentialsConfiguration`` to initialize
the `Credentials` object.
