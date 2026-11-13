# Assistant host inspection

First implementation slice of [assistant epic #124](https://github.com/NavadeepDj/Buildify/issues/124),
tracked by [#125](https://github.com/NavadeepDj/Buildify/issues/125).

The local assistant inspection adapter reads fresh device metrics and runtime
state from the same `ServerBridge` that the AI controller uses. It does not use
dashboard defaults, start a second process owner, or initialize the controller
when inspected independently. This matters because controller hydration may
reconnect a tunnel; inspection itself must stay read-only.

## Integration

Read `assistantInspectionToolsProvider` from Riverpod. It exposes only:

- `get_device_capabilities`, with no arguments.
- `get_runtime_state`, with no arguments.

Both return `InspectionToolResult`. `ok` means a tool name/argument set was
accepted; inspect each reading's `status` before using its value. It does not
mean a service is healthy or that a model fits the host. Unknown tools and any
arguments are rejected before bridge calls. No target-device selector, arbitrary
command, URL or credential is accepted.

Each bridge read has a UTC `readAt`, `source`, status and sanitized value. The
timestamp describes when the read finished, not a health-test timestamp. Reads
are bounded to three seconds by default, are not cached by this service, and
have independent failure outcomes. A timed-out native future cannot be forcibly
cancelled by this adapter; its late result is discarded.

## Measurement boundaries

Memory and disk use GiB (1024 cubed bytes), matching current native metrics.
Missing metrics remain null; malformed, negative or nonfinite values are
discarded and their allowlisted field names recorded. Zero available memory,
free disk and battery are valid observations. Total memory must be positive;
available memory exceeding reported total is discarded conservatively. A
complete metrics reading can still have unknown ABI and runtime availability.

The existing bridge reports total Android memory rounded down to whole GiB.
This adapter does not repair or guess the missing precision. It also does not
attest available runtimes merely because an OS is supported. Architecture and
inference-binary availability remain explicitly null pending dedicated probes.
Only measurements actually returned by a platform are usable; macOS/Linux/iOS
may return unavailable or unsupported data.

Process/tunnel state is an observation, not a readiness or inference test.
`healthVerified` is always false in this slice. A reported stopped process does
not prove a runtime binary is absent. Public URLs, filesystem/model paths,
native error text, stop messages, CPU labels and arbitrary metric fields are
excluded from tool output. Generic failure codes carry no raw exception text.

## Validation and remaining work

`flutter test test/assistant/host_inspection_test.dart` covers fresh/partial data,
malformed values, bridge failure, timeout, independent runtime probes, argument
validation, sensitive-field exclusion and read-only provider integration.

This slice adds no UI, cloud model, execution tool, ranking algorithm, publication
change, remote authorization, model download or deployment. The remaining work
is tracked in #126-#136. Device compatibility and actual inference require later
real-device evidence; tests of this adapter do not certify host readiness.
