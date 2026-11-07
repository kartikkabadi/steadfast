# cedar template

Steadfast now uses Cedar's implementation as its UI template. The owner's authorization covers the reuse. Cedar's repository is left unchanged.

| Cedar source | Steadfast use |
| --- | --- |
| `Sources/Search/Design.swift` | `CedarDesign.swift`: Tone resolution/cache, palette values, TypeScale, Symbols, Radius, Depth, Glass, Dim, Surface, Motion, PrimaryStyle, PressStyle, FocusRing |
| `Sources/Search/Plate.swift` | `Design.swift`: original Card, Titled, Rule, Line, Door, Plate and Hunt components; the search clear button uses Cedar's QuietToolButton. Steadfast adds PageHeading, Tag, EmptyState and one shared `choice` look for every pickable option |
| `Sources/Search/App.swift` | transparent native window configuration |

Steadfast uses its own royal-blue accent, with a lighter blue for dark appearances. Browser theme plumbing was omitted. Clarity's cross-thread value uses a Swift 6 mutex instead of an unsafe global. Browser onboarding actions were replaced with Steadfast's service setup. Copy, the shield symbol, and the blocking workflow remain specific to Steadfast. The source template targets macOS 26 or later, matching Cedar's native Liquid Glass baseline.

Cedar components are © 2026 Kartik Kabadi. The upstream Search MIT notice is retained in `LICENSE-Search`. No browser engine, browser data, licensing code, terminal runtime, extensions, or Cedar app identity was imported.
