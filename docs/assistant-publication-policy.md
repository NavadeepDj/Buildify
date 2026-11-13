# Model publication policy

Part of #128. New installations and missing/invalid saved policy default to
deviceNetwork: no public model tunnel is automatically started. This describes
public routing, not a change to native listening addresses. Android can still
bind LAN interfaces; Windows currently binds loopback. LAN access and local
inference authentication must be considered separately.

Public intent requires configured API-key protection. Publication additionally
requires that the current controller started the model with that same key.
Hydration cannot prove an existing process's key settings; restart it to publish.
Disabling or rotating the key revokes publication intent. Reconnection and both
named/quick-tunnel entry points enforce the same gate. Revocation removes the AI
route and cancels its retry epoch before awaiting persistence or tunnel shutdown;
a stale quick-tunnel start is stopped when its completion arrives.

The shared project gateway is not stopped, because it may serve project routes.
Existing stopped routes return unavailable rather than retaining an active AI
target. This change does not implement service-scoped key management or quotas
tracked by #98. No anonymous public AI sharing is added.

The assistant UI will expose the deliberate access choice in #130. Existing
automatic model-publication behavior changes to opt-in; keep this draft stacked
with its UI follow-up when evaluating the user experience. Full public-key and
race behavior still needs real Android/Windows evidence under #131/#98.
