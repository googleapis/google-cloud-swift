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

import PubSubConformanceProtos

enum CapabilitiesBuilder {
  static func buildResponse() -> Pubsub_Conformance_V1_GetCapabilitiesResponse {
    var defaults = Pubsub_Conformance_V1_ClientDefaults()
    // Publisher defaults
    defaults.publishBatchCountThreshold = 100
    defaults.publishBatchByteThreshold = 1_000_000
    defaults.publishMaxRequestBytes = 10_000_000
    defaults.publishBatchDelayMs = 10
    defaults.publishTotalTimeoutMs = 600_000
    defaults.publishFlowControlMaxMessages = -1
    defaults.publishFlowControlMaxBytes = -1
    defaults.publishFlowControlBehavior = .ignore
    defaults.publishCompressionEnabledByDefault = false
    defaults.publishCompressionBytesThreshold = 240
    defaults.publishCompressionAlgorithm = .gzip
    defaults.publishHedgingDelayMs = 1_000
    defaults.publishHedgingMaxTokens = 50
    defaults.publishHedgingRefillRatio = 0.1
    // Subscriber defaults
    defaults.subscriberMaxOutstandingMessages = 1_000
    defaults.subscriberMaxOutstandingBytes = 104_857_600
    defaults.subscriberMaxExtensionMs = 3_600_000
    defaults.subscriberMinAckExtensionMs = 10_000
    defaults.subscriberMaxAckExtensionMs = 600_000
    defaults.subscriberAdaptiveAckExtension = true
    defaults.subscriberPerStreamFlowControl = true
    defaults.subscriberDefaultStreamAckDeadlineSeconds = 60
    defaults.keepalivePingIntervalMs = 30_000
    defaults.keepalivePongTimeoutMs = 15_000
    // Retry defaults
    defaults.retryInitialDelayMs = 100
    defaults.retryMaxDelayMs = 60_000
    defaults.retryDelayMultiplier = 1.3

    var response = Pubsub_Conformance_V1_GetCapabilitiesResponse()
    response.clientLanguage = "swift"
    response.clientLibrary = "GoogleCloudPubSub"
    response.clientVersion = "0.1.0"
    response.supportsMonitoring = false
    response.supportsUnaryPull = true
    response.supportsBlockingPublish = true
    response.supportsPublishFlowControl = true
    response.supportsPublishCompression = true
    response.supportsPublishHedging = true
    response.supportsOrderingOptIn = false
    response.supportsSubscriberOrdering = false
    response.supportsKeepalive = true
    response.supportsEodReceiptModack = true
    response.supportsAutoNackOnDrop = true
    response.supportsAckWithResult = true
    response.supportsCustomRetryCodes = true
    response.supportsExactlyOnceDelivery = true
    response.supportsPerStreamFlowControl = true
    response.supportsResumePublish = true
    response.supportsShutdownBehavior = true
    response.supportsShutdownTimeout = true
    response.defaults = defaults
    return response
  }
}
