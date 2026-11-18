# Guided setup QA result — copy per host/model

Status: NOT RUN. Replace fields with observed evidence; do not infer a pass.

## Run identity

- Tester / date / timezone:
- App version, commit SHA, artifact source:
- Windows version/build OR Android device/OS/ABI:
- Total / available memory; free disk; battery/charging:
- llama-server version/build; cloudflared version:
- Selected model / artifact source revision / hash-verification result:
- Fresh download or pre-existing artifact:
- Actual navigation clicks to setup and sharing controls:
- Local network arrangement; separate-network public client if used:
- Route mode (none / quick / named); redact live public address when sharing:
- Authentication enabled? (Never include the key):

## Case results

For each line replace NOT TESTED with PASS / FAIL / BLOCKED / NOT TESTED and add
the evidence reference or a reason. Q00 is the feature/build access gate.

- Q00 — Complete build and normal feature access: NOT TESTED
- Q01 — Prepare without download/start/publication: NOT TESTED
- Q02 — Approve, independent inference, copy URL and stop: NOT TESTED
- Q03 — Cancel active transfer, preserve assets and retry: NOT TESTED
- Q04 — Device/LAN scope and reconnect/reopen behavior: NOT TESTED
- Q05 — Active workload and explicit replacement consent: NOT TESTED
- Q06 — Expired plan and duplicate approval: NOT TESTED
- Q07 — Insufficient/unavailable resources: NOT TESTED
- Q08 — Download network interruption and retry: NOT TESTED
- Q09 — Background/exit/interruption/recovery: NOT TESTED
- Q10 — Artifact integrity fixture: NOT TESTED
- Q11 — Missing runtime / occupied port fixture: NOT TESTED
- Q12 — Explicit protected public inference from another network: NOT TESTED
- Q13 — Missing/wrong/correct-key requests: NOT TESTED
- Q14 — Publication revoke and reconnect race: NOT TESTED
- Q15 — Key change/disable and app reopen: NOT TESTED

## Observations and evidence

- Plan preparation duration:
- Download duration / bytes:
- Startup/warmup duration:
- Displayed inference duration; independent request duration/status:
- Cancel-to-outcome duration; outcome and retry result:
- Public correct-key / missing-key / wrong-key statuses (no keys):
- App responsive while hashing/downloading/starting? Any clipping or overflow?:
- Screenshot/video/log references (sanitized):
- Tested behaviors that differed from the runbook:
- Untested cases, missing fixtures and blockers:
- Remaining partial artifacts or services:

## Bug report — duplicate this section for each failure

- Case ID / short title:
- Exact build, device, model and baseline:
- Reproduction steps:
  1. ...
  2. ...
- Expected:
- Actual, including status/error code and duration:
- Reproducibility (attempts affected / total):
- Sanitized evidence:
- Impact / suggested severity:
- Issue or private report link:
- Retest build / date / outcome:

## Sign-off

- Local guided setup: NOT VALIDATED
- Public sharing: NOT VALIDATED
- Open issues / exclusions:
- Tester recommendation:
- Maintainer decision and date:
- Cleanup complete / remaining owner action:

Reference: [manual procedure](assistant-guided-setup-qa.md).
