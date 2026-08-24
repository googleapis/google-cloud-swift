# ``GoogleCloudStorage``

[buckets]: https://docs.cloud.google.com/storage/docs/buckets
[objects]: https://docs.cloud.google.com/storage/docs/objects

Cloud Storage is a managed service for storing unstructured data. Store any
amount of data and retrieve it as often as you like.

## Overview

This library implements types to work with Google Cloud Storage.

Use ``StorageClient`` to upload (write) and download (read) [objects]. A default
initialized `StorageClient` works in most cases. The client supports resumable
uploads, single-shot uploads, full and partial object reads. To provide data for
uploads implement the ``SeekableUploadSource`` or the ``UploadSource``
protocols.

Use ``StorageControlClient`` for other operations, including listing, deleting,
updating object metadata, object rewrites, and object composition. The same
type can be used to perform all operations on [buckets].

Use ``StorageClientProtocol`` and ``StorageControlProtocol`` if you want
to mock the clients in your tests.
