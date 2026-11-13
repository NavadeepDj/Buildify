# Local model setup adapter

Part of #127/#131, stacked after the operation journal. The concrete controller
adapter rechecks resources, respects approved workload interruption, downloads
only the catalog's pinned Hugging Face artifact, verifies size and streamed
SHA-256, selects the model, applies the approved context size, starts it, and
requires a bounded real inference response before success.

The first setup workflow is device/LAN only. Public scope is refused here until
public authentication and route verification are implemented. Existing explicit
network controls can manage public intent under the publication policy.

Context size is part of the approval digest and is forwarded through the Dart
bridge to Android/desktop llama-server as --ctx-size. Unspecified context retains
the existing manual behavior. Explicit values are bounded to 128–8192 tokens.

Assistant downloads use a separate .assistant.part artifact, an exact byte limit
and idle timeouts. Cancellation closes that operation's client and stops only a
model it attempted to start. Existing models are never deleted by cancellation.
Hash verification reads a stream rather than loading multi-gigabyte weights into
memory. A mismatched pre-existing file is refused for explicit owner recovery.

The inference verifier contacts loopback only, does not follow redirects, caps
response bytes at 64 KiB and applies an overall timeout. Prompts/responses and
credentials do not enter operation records. The small synthetic greeting proves
one inference request; it is not a quality, throughput or capacity benchmark.

Tests exercise response shape/auth/redirect/size limits, artifact identity and
native context forwarding. Actual Android/Windows hardware evidence remains
open under #131. Do not interpret mocked tests as a real hosted model run.
