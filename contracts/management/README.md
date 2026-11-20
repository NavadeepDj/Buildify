# HostAny management API contract

This package is the public source of truth for the first proposed management API
slice in [#83](https://github.com/NavadeepDj/Buildify/issues/83). It does not contain
the private backend and does not claim the endpoints are deployed.

- `openapi.json`: routes, wire fields, schemas, authentication and errors.
- `generated/management.d.ts`: generated TypeScript types; do not edit by hand.
- `test/`: examples of accepted and rejected wire payloads.
- `devices/openapi.json` and `generated/devices.d.ts`: separate **proposed,
  unimplemented** #84 enrollment interface. See the
  [device lifecycle and handoff](../../docs/api/device-enrollment-v1.md).
  Its presence does not change the reviewed foundation or deployed backend pin.
- [Foundation policy](../../docs/api/management-v1.md): ownership, CORS, limits,
  redaction, release gates and authentication requirements.

## Check a change

Use Node 24 and npm, then run from this directory:

```sh
npm ci --ignore-scripts
npm run check
```

To intentionally change the contract, edit `openapi.json`, run `npm run generate`,
review and commit the generated diff, then run `npm run check` again. CI checks
OpenAPI validity, wire examples and generated-file drift. This is not a substitute
for private backend authentication/authorization and integration tests.

The lint/generate/check commands also cover the separate device proposal. Edit
`devices/openapi.json` for enrollment changes; never edit generated types by hand.

The lockfile pins the toolchain. A scoped `minimatch` override for
`openapi-typescript` selects patched version 11.0.1 for GHSA-g3hv-75wg-m249; the
generator and schema checks pass with that override. CI also audits development
dependencies and fails on moderate-or-higher advisories. Do not suppress audit
findings or force unrelated dependency upgrades.

## How both repositories share it

The public Flutter repository owns this specification. The private
`NavadeepDj/hostany-management` repository vendors an exact Git commit and records
SHA-256 digests for the specification and generated types. Its checks verify those
bytes and run response-schema examples against the same contract. Updating public
main must not silently change a deployed backend.

For development, a draft contract commit can be pinned explicitly and marked as
unreleased. Before deployment, approve/merge the contract and pin a reviewed
commit. No mutable `main` download is used as a runtime dependency.

Future Flutter adapters can generate Dart clients/models from this OpenAPI file;
this first contract change intentionally does not touch app screens, runtime
services or shared Flutter dependencies. The existing Supabase signup path does
not call the new proposed management API yet.

## Compatibility

Treat `v1` as the public compatibility boundary. Version `0.1.0` is the initial
unreleased specification. Do not rename fields or change required values in a
released v1 response without an explicit compatibility decision. Client and
backend release checks must test supported older clients as well as current code.
The strict schemas catch unexpected response fields: adding fields therefore
requires coordination and fixture updates, not an assumption of compatibility.

This repository's MIT license covers this public contract and generated interface.
It does not change the private backend's licensing or publish its implementation.
