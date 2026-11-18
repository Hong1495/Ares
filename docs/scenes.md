# Scenes

Scenes save selected settings for the current subscription. Use **Create Scene** to choose which settings to capture. Saving or editing a scene does not activate it. Select the scene and use **Review Switch** to see what would change before applying it.

## Example: Daily and US Browser

1. Save a `Daily` scene with only **Local Rules** selected.
2. In **Applications**, route a browser to the `United States` policy group in Rule mode, then save a `US Browser` scene with only **Local Rules** selected.
3. Switch between the scenes. They replace the saved local rule set, including application routes. Existing policies, DNS overrides, mode, and saved choices are left alone when their sections are excluded.
4. After a successful switch, use **Check App Routes** to inspect evidence from new connections. **Core confirmed** refers to activation, not a traffic match. Use **Undo** to restore the previous settings while the review baseline still matches.

In the editor, **Keep Current** leaves a section unchanged, **Restore Inheritance** clears its local overrides, and **Use Scene Settings** applies the saved content. DNS and advanced policy/listener values are summarized by the setting or group they affect, without exposing credential values in the preview. Rule changes supported by the application editor show the exact executable and target; other rules show additions, removals or ordering changes. Local rules are shared across subscriptions in Rule mode.

Existing complete snapshots retain their previous behavior. A library containing partial scenes uses schema 2 so older versions cannot silently reinterpret excluded sections as instructions to clear overrides. Automation remains opt-in and uses the same scoped changes and review safeguards.
