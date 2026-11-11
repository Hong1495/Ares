# Ares typography

Use `DS.Typography` for explicit application typography. Native controls can inherit their system font.

| Role | Native style | macOS default | Use |
| --- | --- | --- | --- |
| body | body | 13 pt | Primary labels, navigation, controls |
| secondary | callout | 12 pt | Secondary content, compact rows |
| metadata | subheadline | 11 pt | Supporting values, timestamps |
| caption | caption | 10 pt | Chart axes, compact badges |
| title | title3 | 15 pt | Small feature titles and prominent values |
| sectionTitle | title2 | 17 pt | Dialog/section titles |
| metric | title, rounded, medium | 22 pt | Dashboard speed and latency |

Use regular weight by default, medium for selection, and semibold for important labels. Use monospaced text for IPs, code and aligned technical values; use monospaced digits for changing metrics. Symbol artwork can use a separate size. Avoid arbitrary fractional font sizes and text below 10 pt.

Dashboard's flat section labels use callout in secondary color; data values provide the emphasis. Full card titles elsewhere use body semibold. This is a role distinction, not a per-page font scale.

Source: https://developer.apple.com/design/human-interface-guidelines/typography

Verification limits: shared components and representative preview pages inspected; production service-backed layouts and larger accessibility text configurations require further isolated fixtures or a disposable VM.
