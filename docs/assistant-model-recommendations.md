# Model recommendation policy

Part of #126. The recommendation service filters resource/runtime constraints
before ranking eligible models by task, verified installation and speed/balanced/
quality preference. Ranks are editorial catalog policy, not throughput benchmarks.
All results include explicit blocker codes; unknown runtime/model support never
becomes a positive compatibility claim.

Catalog v2 extends existing display fields without removing them. Exact artifact
sizes, LFS SHA-256, immutable repository revisions and model-card license labels
were read from the three existing Hugging Face repositories on 2026-11-13:

- https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF
- https://huggingface.co/Qwen/Qwen2-1.5B-Instruct-GGUF
- https://huggingface.co/bartowski/Phi-3-mini-4k-instruct-GGUF

Downloads now reference immutable revisions. These are upstream metadata, not a
claim that weights have been downloaded or model licenses independently audited.

The initial 2048-token budget conservatively reserves 512 MiB for runtime
overhead and 1 GiB for context, plus 512 MiB free host memory. These are explicit
planning budgets, not measured KV-cache sizes or a startup guarantee. Each model
has an empty testedConfigurations list until real evidence is collected.
The download budget keeps 256 MiB free disk beyond artifact size. A verified
installed artifact with matching ID, bytes and hash avoids another download;
mere file existence does not count as verification.

Metrics and runtime evidence must be no more than 30 seconds old and cannot be
future-dated. Runtime evidence must match the observed platform and explicitly
identify supported model IDs. The caller must supply actual verified runtime
evidence; the service does not infer it from an OS name or dashboard state.
Existing inspection tools currently leave binary availability unknown. The
runtime evidence adapter and actual device profiles remain prerequisites for
automatic execution; this policy layer does not start any process or network job.

Run flutter test test/assistant/model_recommendation_test.dart. Tests cover
metadata migration, deterministic ranking, freshness, format/runtime refusal,
memory boundaries, disk reserve and installed-file identity.
