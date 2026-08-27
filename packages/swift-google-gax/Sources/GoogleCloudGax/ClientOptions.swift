// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import Logging
import GoogleCloudAuth

/// The configuration for a new client.
///
/// Use this type to configure clients in the Google Cloud client libraries for Swift libraries.
public struct ClientOptions: Sendable {
  /// Create an instance without any overrides.
  public init() {}

  /// Override specific values using the `Then` idiom.
  ///
  /// ## Example
  /// ```
  /// let options = ClientOptions().with { $0.endpoint = "https://private.googleapis.com" }
  /// ```
  public func with(_ config: (inout Self) -> Void) -> Self {
    var copy = self
    config(&copy)
    return copy
  }

  /// Overrides the default endpoint for the client.
  ///
  /// Each client defines a default endpoint (typically `https://${service}.googleapis.com`), applications may need to
  /// override in many circumstances, including:
  /// - Using a regional endpoint, such as `https://${service}.${region}.rep.googleapis.com`.
  /// - Using a locational endpoint, such as `https://${service}-${region}.googleapis.com`.
  /// - Using the API in a VPC-SC environment, where `https://private.googleapis.com` serves as the endpoint for all
  ///   APIs.
  /// - Using the API against an emulator or some other test environment.
  ///
  /// Only the scheme and authority (host and port) components of the endpoint are used, the path
  /// and/or query parameters have no effect.
  public var endpoint: String? = nil

  /// Overrides the default credentials for the client.
  ///
  /// `Credentials` defines how the client authenticates to Google Cloud APIs. Without an override, the client uses
  /// [Application Default Credentials]. This works well in most deployment and development environments, use this
  /// override if your application cannot use the default.
  ///
  /// [Application Default Credentials]: https://docs.cloud.google.com/docs/authentication/client-libraries
  public var credentials: Credentials? = nil

  /// Enables logging and sets the logger.
  ///
  /// When logging is enabled, the client will log the full contents of each request, response, and
  /// error using the this logger. The `Logger` type is defined in Apple's [swift-log] package.
  /// Consult the documentation of this package for details on how to initialize and configure a
  /// logger.
  ///
  /// > Warning: Consider the contents of these requests and responses before enabling them in
  /// production environments, as the request or responses may include sensitive data.
  ///
  /// The requests, responses, and errors are all logged as the `.debug` level. The in addition
  /// to any metadata already set by the application
  ///
  /// [swift-log]: https://swiftpackageindex.com/apple/swift-log/
  public var logger: Logger? = nil

  /// Configures the client's retry policy.
  ///
  /// By default the clients use ``BaseRetryPolicy`` with a limit of 60 seconds or 10 attempts.
  /// Whichever limit is reached first stops the retry loop.
  public var retryPolicy: any RetryPolicy = defaultRetryPolicy()

  /// Configures the client's backoff policy.
  ///
  /// By default the clients use ``ExponentialBackoff`` with the default initialization.
  public var backoffPolicy: any BackoffPolicy = defaultBackoffPolicy()

  /// Configures the client's retry throttler.
  ///
  /// By default the clients use an ``AdaptiveThrottler`` with the default configuration.
  public var retryThrottler: any RetryThrottler = defaultRetryThrottler()

  /// Configures the client's polling error policy.
  ///
  /// By default the clients use ``BasePollingErrorPolicy`` with a limit of 30 minutes.
  public var pollingErrorPolicy: any PollingErrorPolicy = defaultPollingErrorPolicy()

  /// Configures the client's backoff policy.
  ///
  /// By default the clients use ``ExponentialBackoff`` with an initial backoff of 1 seconds,
  /// doubling each time the default initialization.
  public var pollingBackoffPolicy: any BackoffPolicy = defaultPollingBackoffPolicy()
}

func defaultRetryPolicy() -> any RetryPolicy {
  BaseRetryPolicy().withTimeLimit(.seconds(60)).withAttemptLimit(10)
}

func defaultBackoffPolicy() -> any BackoffPolicy {
  ExponentialBackoff()
}

func defaultRetryThrottler() -> any RetryThrottler {
  AdaptiveThrottler()
}

func defaultPollingErrorPolicy() -> some PollingErrorPolicy {
  BasePollingErrorPolicy().withTimeLimit(.seconds(30 * 60))
}

func defaultPollingBackoffPolicy() -> some BackoffPolicy {
  try! ExponentialBackoff(
    config: ExponentialBackoffConfig().with {
      $0.initialDelay = .seconds(1)
      $0.maximumDelay = .seconds(300)
    })
}
