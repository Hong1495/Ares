# Third-party notices

## mihomo

- Project: https://github.com/MetaCubeX/mihomo
- License: GNU General Public License v3.0
- Ares communicates with mihomo as a separate executable through its local API.
- Version 1.0.0 release packaging pins mihomo v1.19.34. The GPL license, exact upstream source archive (including its build scripts) and upstream release metadata are supplied alongside the application downloads. License and source information are also included in the app's Resources directory.
- No compiled core is stored in the current source tree. Packaging downloads the matching pinned upstream binary.

## Sparkle

- Project: https://github.com/sparkle-project/Sparkle
- Version: 2.9.6
- License: see [Packages/Sparkle/LICENSE](Packages/Sparkle/LICENSE), including its dependency notices.
- The framework is downloaded from the official release using a pinned SHA-256 checksum.

## Country database

The historical `Country.mmdb` has no verified provenance in this repository. It has been removed from the source tree and is excluded from the 1.0.0 distribution. GeoIP resources are managed by the core when required by the selected configuration; availability may depend on network access.
