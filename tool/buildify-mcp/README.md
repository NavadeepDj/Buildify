# Buildify owner MCP prototype

The official MCP SDK exposes the tool manifest from the running Windows app
over stdio. Bolna uses custom HTTP functions generated from that same manifest;
the live voice agent is not assumed to be a native external-MCP client.

Install with `npm ci` in this directory. Start the app and tunnel using
`scripts/start-status-probe.ps1 -Tunnel`, then run
`node scripts/connect-bolna-status.mjs` from the repository root. The connector
updates the existing demo agent rather than making a new agent on every run.
`mcp.example.json` shows a client configuration. It contains no credential.
The adapter reads the temporary token from ignored `build/status-probe/session.json`.

Run `npm test` here with the paired app open. This uses the official MCP client
and stdio transport to discover the real tools, read model state/catalog, and
check rejection of remote approval arguments.

For an owner-initiated browser voice call, run `node scripts/bolna-webcall.mjs`
and open `http://127.0.0.1:19001`. Click **Call Buildify** and grant microphone
access yourself. The local server mints short-lived Bolna sessions; the page
never receives the account API key. The server permits up to eight session
mints per run, at least 20 seconds apart. Calls use the account's Bolna balance.

State changes require review in the local action inbox. A model setup has its
own existing **Approve and run** screen. No remote approval tool is exposed.
Advanced build configuration, account authorization, local file selection and
secrets stay in the existing local UI. This is a single-owner paired demo;
multi-account enrollment, arbitrary remote devices and dial-in phone routing
are not implemented by this adapter.

The app supports one active project session. Starting another project may
stop it, run saved scripts, and start its configured public route. These effects
are shown in the local review. Tool success reports the specific observation:
import is not deployment, process state is not inference, and local HTTP health
is not public reachability.
