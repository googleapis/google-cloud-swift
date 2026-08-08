# Supported Swift versions

[Client libraries explained]: https://cloud.google.com/apis/docs/client-libraries-explained
[semantic versioning]: https://semver.org/
[swift package update]: https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/resolvingpackageversions/
[swiftly update]: https://www.swift.org/swiftly/documentation/swiftly/update-toolchain/
[README]: https://github.com/googleapis/google-cloud-swift#readme

<!-- reference links at the top for Swift DocC -->

The Swift client libraries support Swift 6.3 and higher. This document provides
additional information and best practices to keep your toolchain and libraries
up-to-date.

## Minimum supported Swift version

The Swift client libraries support Swift 6.3 and higher. For more information on
Cloud client libraries, see [Client libraries explained].

Our Swift client libraries increment the major version when dropping
compatibility with a Swift major version. For more information about the use
of major and minor versions, see [Semantic Versioning].

The libraries are tested against Swift versions released at the time the client
libraries were released. To find out what versions we used in our testing,
consult the projects [README] file.

## Recommended version for new development

When starting a new project, we recommend choosing the current release of Swift.
This ensures that your runtime is within the supported Swift releases and
receives critical security patches.

## Keep your production systems current

Ensure that you receive critical security and bug fixes by keeping your
production systems on supported Swift toolchains. Use [swiftly update]
to automatically update your version of Swift and [swift package update] to
automatically update the Rust dependencies in your project.
