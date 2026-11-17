# Application routing

Applications manages persistent local rules. Activity observes runtime traffic.
The page retains its independent entry and Activity's Route Application action
opens the same editor.

## Workflow

1. Add discovered applications or choose an application/executable from the Mac.
2. Select the application in the native table. Route reflects the saved exact-path
   overrides; it never defaults to Direct as if that were the saved state.
3. Review the explicit executable scope, choose Follow rules, Direct, Block or a
   policy/node, and Apply. Follow rules removes local exact-path overrides only.
4. Open new connections in that application. Verification uses core-reported
   processPath, rule type, rule payload and route chain. Connections predating the
   change cannot verify the new configuration.

The table initially contains configured applications, plus entries explicitly
added during this visit. Active helper paths for those applications join their
display group. Discovery is separate from management. Paths observed in this
visit remain available after a connection closes. Grouping shares Activity's app
identity; grouping never changes the scope of a PROCESS-PATH rule.

Selecting a table row selects all known paths and expands the executable scope
when more than one path is present. Executables displays each exact path with a checkbox and its
saved route. Helpers are not inferred from an app bundle or included silently.
Adding an app bundle from disk selects its main executable; other helpers can be
selected when reported by the core.

## Truthful state

- Route is the local configured override, not a simulated effective route through
  all subscription/domain/IP rules. Follow rules makes no fixed-route claim.
- Mixed indicates different overrides or a mixture of overridden/inherited paths.
- Verified requires new matching evidence for every known executable in the row.
  Partial evidence or an unconfigured known helper remains Partly verified.
- Different route indicates contradictory exact-path rule/chain evidence.
- No connection is Pending, including Block. Absence is not proof.
- Unreadable runtime is Unavailable; Global/Direct mode is Rule mode required.
- Duplicate exact-path rules are exposed. Applying a target replaces duplicates.

Connection evidence and rule details are optional diagnostics under the editor.
Visible pages read connections every ten seconds while active, with a manual
reload of configuration and connections. No background route mutation or
automatic connection termination is introduced. Configuration changes and Undo
retain existing revision guards and validated activation/rollback transactions.

## Visual alignment

The management table stays primary. It uses the same 16-point page insets,
rounded content surface, 20-point application icons and body/metadata hierarchy
as Activity. Search and actions use the shared CollectionTools component.
Selection reveals a compact editor above the table: application and executable
scope on the left, native route picker and Apply on the right. Detailed paths
expand for multi-executable applications so the mutation scope remains visible;
connection evidence is opened only when needed. No duplicate page heading or
permanent explanatory footer is added to the embedded page.

## Validation boundary

Package tests cover saved-route and verification semantics. The production view
model runs against an inert service for grouping, helper selection, apply,
inheritance, undo, stale state and failure recovery. Existing coordinator tests
cover actual local-rule transactions. Native preview uses only synthetic state.

Owned-loopback mihomo tests verify rule acceptance, traffic restoration and
fallback. On this Mac the unprivileged fixture cannot resolve executable identity;
actual process-specific matching remains a privileged/local-app acceptance item.
These tests do not change host proxy, DNS or TUN settings.
