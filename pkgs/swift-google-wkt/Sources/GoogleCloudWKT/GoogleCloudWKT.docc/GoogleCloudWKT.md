# ``GoogleCloudWKT``

This package provides core types used in the Google Cloud Client Libraries for
Swift.

## Overview

This library provides common types used in most client libraries. While most
fields have natural representations as Swift types, some field types require
special treatment. Notably:

- ``Timestamp``: a point in time. The client libraries do not use
  `Foundation.Date` because the valid range and precision are different.
- ``Duration``: a time duration. Likewise, the client libraries do not use
  `Foundation.Duration` because the valid range and precision are different.
- ``FieldMask``: a type to define what the fields affected by an update or
  returned by a request.
- ``Any``: a type that can contain any struct send to and from Google Cloud
  APIs.
- ``Empty``: an empty response or request, rarely used directly as the client
  libraries automatically convert this to `Void`.

## Embedded JSON objects

Some APIs use JSON to represent some parts of their request and response. Look
at the definition of ``Struct``, ``Value``, ``ListValue`` and ``NullValue`` for
more details.

## Optional values

Some APIs use the following types to represent optional fields. Their usage is
quite obvious from the name, except for (maybe) ``BytesValue`` which represents
an optional sequence of bytes, analogous to `Data?` in Swift.

- ``BytesValue``: optional `[UInt8]` field.
- ``StringValue``: optional string field.
- ``DoubleValue``, ``FloatValue``: optional floating point fields.
- ``Int32Value``, ``Int64Value``, ``UInt32Value``, ``UInt64Value``: optional integer fields.
- ``BoolValue``: optional boolean field.

## The recursive field wrapper

Some Google Cloud APIs use structs where one field may contain an instance of
the type that contains the field, maybe indirectly through some intermediate
data type. To avoid defining structs of infinite size, such fields are wrapped
in the ``Recursive`` wrapper.

## API introspection

Rarely some APIs consume API definitions as part of their requests or responses.
We don't provide a full list here as the types are so rarely used. If this is
of interest a good place to start is the ``Api`` type.
