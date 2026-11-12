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

The historical `Country.mmdb` has no verified provenance in this repository and is not distributed. When required, Ares downloads the core's default datasets from [MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat), with a jsDelivr mirror of that project's release branch as a fallback. The upstream project publishes its license and data-source notices. Custom `geox-url` sources are preserved. Validated resources are cached locally and reused for normal and TUN configurations. No geodata is bundled with Ares.

## Yams

- Project: https://github.com/jpsim/Yams
- Version: 5.1.3 (pinned)
- License: MIT, including the bundled LibYAML notices in [Packages/SubscriptionKit/Yams-LICENSE](Packages/SubscriptionKit/Yams-LICENSE).
- Parses saved subscription metadata without running a proxy core or making network requests.
