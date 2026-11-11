# Ares interface baseline

Reference: main / remote HEAD `fed3329d4547349e4c058b010200cb8d81259598`
confirmed with `git ls-remote origin HEAD` on 2026-11-11.

Bee is a reference for the window framework only: unified toolbar, compact
sidebar, monochrome navigation symbols, native selection, restrained surfaces.
Ares content requirements come from the committed baseline, not the later
uncommitted redesign. No generated images are used by the implementation.

| Baseline content | Current presentation |
| --- | --- |
| Core state/version | Runtime summary; full details and updates in diagnostics |
| System proxy, HTTP/SOCKS/API ports | Connection controls and runtime summary |
| TUN and MITM | Connection controls |
| Rule / Global / Direct | Graphical mode buttons |
| Current group, node, latency | Current Proxy information section |
| Public/local IP and network type | IP information section |
| Google, GitHub, Gemini connectivity | Connectivity section |
| Upload/download graph | Primary chart with inspectable history |
| Subscription | Always-visible configuration grid |
| DNS and bypass patterns | Always-visible configuration grid |
| MITM certificate/ports/scope | Always-visible configuration grid |
| Core/system information | Always-visible configuration grid |
| Activity, policies, topology, routing, analysis, logs, settings | Existing routes retained in native split navigation |

Existing working-tree service changes remain in place. This UI pass has not
changed production startup/termination behavior and has not run it on the host.
