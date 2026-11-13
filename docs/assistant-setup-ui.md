# Guided model setup

Part of #130, stacked on the controller adapter (#127/#131). Open the model
setup assistant from the AI shell toolbar. Choose task and preference, prepare
a resource-budgeted candidate, review download/memory/context/access/interruption,
and explicitly approve execution. Runtime compatibility is labeled unverified
until actual startup/inference succeeds. No cloud reasoning is simulated.

The app-scoped setup provider keeps progress while navigating between screens.
It uses the real controller adapter and a journal in application support. Cancel
targets the active operation. Failure requires reviewing state and preparing a
fresh plan; interrupted jobs are not replayed automatically.

Successful results show the locally verified base URL, model identity, measured
single-request duration and authentication guidance. Device/LAN availability is
platform-dependent. The Network screen separately exposes explicit public intent
with API-key setup/restart guidance. Scope writes are serialized so a late save
cannot restore older public intent after a private decision.

Cloud request interpretation and general conversation require the hosted planner
contract/backend in #129. This screen accurately describes itself as guided
setup until that service exists. Voice, remote hosts, automatic remediation and
project deployment are not represented by fake controls or sample successes.
