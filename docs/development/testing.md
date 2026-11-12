# Development and testing

## Preserve the host's network

A development machine may depend on an existing proxy connection. Build and test without disrupting that connection.

- Do not launch the production Ares application or a normal Debug build on the
  host for UI inspection or tests. Startup restores network settings and starts
  the core; termination also modifies system proxy settings.
- Do not stop existing proxy processes, change system proxy settings, change
  routes/DNS/TUN interfaces, install helpers or certificates, or invoke privilege
  setup as part of development verification on this host.
- Do not attempt to restore inferred network settings. Without a known baseline,
  report the observed state and let the developer manage the active connection.
- Compilation and source inspection are allowed. Do not run an app-hosted test
  suite on the host until its startup and teardown isolation has been verified.
- UI verification must use a separate preview executable with mock data and
  independent storage. It must not instantiate production service singletons,
  include the production app delegate, start cores/listeners, call local core
  APIs, or perform network/privilege/certificate operations. A different bundle
  identifier, port, or disabled toggle alone is not adequate isolation.
- Tests that require real proxy services, TUN, system configuration, privilege
  changes, or production startup/termination must run in a dedicated disposable
  VM with its own configuration and network stack, never on this host.

These constraints also apply to subprocesses and test teardown. Keep the
existing uncommitted work when implementing the interface redesign.

## Safe local checks

```sh
scripts/test-safe-functions.sh
python3 -m unittest discover -s scripts/tests -p "test_*.py"
scripts/preview-ui.sh --open
```

The preview has mock data and no production services. Use a disposable VM for live proxy, privilege, certificate and update-installation tests.

## Saved subscription UI regression

Run `scripts/preview-subscription.sh --open` to exercise the production ProxiesView with mock services, a stopped runtime and a synthetic 32-node subscription. Any call to a core operation traps immediately. No production delegate, service implementation or core binary is linked. Verify both Rule and Global lists, search, group expansion and disabled selection/latency actions.

`swift test --package-path Packages/SubscriptionKit` tests YAML block/flow/JSON forms, anchors, Unicode, duplicates, provider-only profiles and malformed input. The optional `ARES_READONLY_PROFILE` environment variable enables a local 32-node/2-group acceptance fixture; it is never copied into the repository or logged.
