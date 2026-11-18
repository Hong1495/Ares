# Ares 1.0.19

- **Policies:** create and edit groups directly, including ordered members, provider references, and behavior. Review saved references from routing rules, applications, parent groups, and configured egress targets. Use Compose for changes that need to update groups and rules together.
- **Readback:** see which groups come from the subscription, which have local changes, and which the running core has confirmed. Member and selection data refresh when the running core changes and while Policies is open. Saved references do not certify live traffic matches or probe parameters.
- **Updates:** automatically retry transient failures when checking the update feed. The update indicator appears beside the window controls when a new version is found. Manual checks remain available.

Requires macOS 14 or later on Apple Silicon. Includes mihomo v1.19.34. Update archives use Sparkle Ed25519 signatures; the app is ad-hoc signed and is not Apple-notarized.
