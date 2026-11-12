# Settings convergence — local build 901.8

## Presentation

- Native segmented category selector, shared card/row typography, no repeated pane title or description.
- Category bar and content share an 820-point maximum width, centered in the detail area; smaller windows fill available width.
- Switches and text inputs align in the right-hand column. MTU and intervals include units.
- Activity statistics use 18-point medium-weight numbers and 11-point units on a shared baseline.
- Isolated preview inspected: General, Network, TUN, MITM, Rules and Activity title. Latest dark-mode and minimum-window checks were not completed.

## Functional review

| Setting / action | Result |
| --- | --- |
| Start with macOS | Read actual SMAppService status, register/unregister only on user action, show permission/error state. |
| Menu-bar-only launch | Startup now uses the same default as Settings. |
| Theme / menu latency | Existing ThemeService and menu presentation bindings retained; theme reset explicitly applies appearance. |
| Log level | Runtime API must succeed before committing the displayed preference; failure retains previous value. |
| Automatic / manual update | Existing Sparkle configuration and availability checks retained; reset restores automatic checking. |
| Cache | Clear URL response cache and legacy temporary cache only; subscriptions and routing data retained. |
| Reset | Confirmation, login-item failure handling, resets MITM/fingerprint/update preferences too; keeps certificates, subscriptions, TUN state. |
| Ports / LAN / IPv6 / DNS | Draft inputs, validation, config validation before restart; proxy updated only after readiness. Fixed DoH bootstrap and YAML slash escaping. |
| TLS fingerprint | Existing behavior supplies a default only to supported nodes without their own fingerprint. UI wording corrected to match. |
| TUN switch | Existing runtime transition retained. Pending edits must be applied or discarded first. |
| Stack / MTU / device / route / detect / timers | Configuration reads saved MTU/device; subscriptions cannot override owned timers. Dedicated TUN ports remain separate. |
| Certificate | Checks trust instead of file existence; exposes install/export failures. No keychain was modified during verification. |
| MITM ports / hosts | Apply refreshes display filter and upstream port; TUN rule generation uses IP predicates for IP entries. UI explains mode-specific behavior. |
| Bypass / local rules | Explicit Apply, wildcard/IP/CIDR conversion, rules retained without a subscription. Invalid generated config rejected before stopping core. |

## Verification and limits

- Release arm64 build passed.
- 98 isolated tests passed; SubscriptionKit ran 9 tests with 1 optional fixture skipped, no failures.
- Normal and TUN configurations (custom MTU/device, DoH DNS, IPv4/IPv6 rules) passed bundled mihomo `-t` in a temporary directory.
- UI fixture links no production services, preferences, core or privilege code.
- Actual login-item registration, certificate installation/export, update installation, proxy changes, live restart/recovery and TUN activation were not executed against the user's running installation. They were reviewed in source; corresponding pure configuration/transition tests do not substitute for live runtime acceptance.
