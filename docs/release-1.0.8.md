# Ares 1.0.8

This release simplifies the menu bar panel to match the main window. Requires macOS 14 or later on Apple Silicon; Intel Macs are not supported.

- Replaces the previous status presentation with Country, Exit IP, optional IP Risk, and Latency from the same application state used by Dashboard. Values use the shared numeric typography and latency colors; unavailable values display a dash.
- Removes the top app/status heading, selected node row, proxy switches, and routing mode selector from the panel. Network controls remain available in the main window.
- Keeps live download/upload rates and compact actions for opening Ares, Activity, Settings, and quitting.
- Adds an isolated menu preview for checking layout without starting the proxy core or changing network settings.

Includes the Apple Silicon mihomo v1.19.34 core. Existing installations with automatic updates configured can install this release through Check for Updates. Update archives use Sparkle Ed25519 signatures; the app is ad-hoc signed and is not Apple-notarized.
