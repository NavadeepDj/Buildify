# Approved model operations

Part of #127. A model plan binds operation/model identity, artifact hash/bytes,
access scope, interruption permission and expiry. LocalPlanApproval is minted by
an explicit UI approval, has no JSON constructor and is not a cloud tool input.
Changing any plan field changes its digest and invalidates the approval.

The executor journals each step before its side effect and succeeds only after
inference verification. A matching completed operation is returned without replay.
An interrupted operation becomes needsReview: it must be reconciled against the
actual runtime before a new approved attempt. This deliberately avoids claiming
exactly-once side effects after a crash. Failed/cancelled jobs need a new plan ID.

One executor serializes host-conflicting work. Share it through the app container;
this is not a distributed/multi-process lock or a replacement for #87. Cancellation
is cooperative; the runtime adapter must interrupt its owned work. Uncancellable
native work must finish/reconcile before another operation can own the host.

The file journal uses an app-selected directory and atomic file replacement.
Operation IDs cannot escape that directory. Store only sanitized fixed outcome
codes. Journal/storage failure is not permission to continue an unrecorded action.
No automatic replay, public route change, raw shell or secret-bearing log is added.

Runtime/controller adapter integration follows separately. Unit tests use fake
runtime actions; they do not certify real model startup or cancellation behavior.
