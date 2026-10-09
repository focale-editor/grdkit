# GRD format support

This document describes the GRD structures accepted by GrdKit, the shared gradient model exposed to applications, and the boundaries of source reconstruction. Multibyte numeric values are big-endian.

## Container layout

Every library starts with the same envelope:

| Field | Type | Meaning |
| --- | --- | --- |
| Signature | 4 bytes | ASCII `8BGR` |
| Version | `uint16` | `5` for descriptor libraries, `3` for legacy libraries |
| Gradients | variable | Version-specific records described below |
| Trailer | variable | Optional tagged blocks or opaque bytes |

An invalid signature, an unsupported container version, or structural truncation causes a `GrdFormatException` in both decoding modes.

## Version 5 descriptor layout

A 32-bit descriptor version (16) follows, then an Action Descriptor whose `GrdL` item lists the gradients. Each list entry is a `Grdn` object whose `Grad` item holds the gradient, also of class `Grdn`. GrdKit keeps the wrapper in `GrdGradient.descriptor` so that unknown keys survive a round trip, and also accepts entries whose wrapper is the gradient itself.

| Key | Form | Meaning |
| --- | --- | --- |
| `Nm  ` | both | Name |
| `GrdF` | both | `CstS` for custom stops, `ClNs` for color noise |
| `Intr` | custom | Smoothness, 0–4096 |
| `Clrs` | custom | `Clrt` stops: `Clr ` color, `Type` (`UsrS`, `FrgC`, `BckC`), `Lctn` 0–4096, `Mdpn` percent |
| `Trns` | custom | `TrnS` stops: `Opct` percent, `Lctn`, `Mdpn` |
| `RndS`, `Smth`, `ShTr`, `VctC`, `ClrS`, `Mnm `, `Mxm ` | noise | Seed, roughness, transparency, restricted colors, color model, minimum and maximum channel values |

`GrdFile.rootDescriptor` keeps library-level fields, and `GrdGradient.gradient` exposes a `PsGradient` view of each gradient. These views leave the underlying descriptors available for unfamiliar keys and future extensions.

## Version 3 legacy layout

A 16-bit gradient count follows the version, then for each gradient:

| Field | Size |
| --- | ---: |
| Name length, then Latin-1 name | 1 + n |
| Color stop count | 2 |
| Color stops: location (4), midpoint (4), color model (2), four components (8), type (2) | 20 each |
| Transparency stop count | 2 |
| Transparency stops: location (4), midpoint (4), opacity 0–255 (2) | 10 each |
| Reserved | 6 |

Color components follow Photoshop's color structure: RGB and HSB use the whole 16-bit range, CMYK stores 0 for full ink, Lab stores lightness and signed a and b in hundredths, and grayscale uses 0–10000 with 10000 for white. Stop types 1 and 2 are foreground and background stops. Encoding always produces version 5.

Legacy records are converted into the same descriptor-backed `PsGradient` model as version 5 records. Unsupported legacy color models produce warnings in tolerant mode; their process-color values cannot be reconstructed from the resulting gradient.

## Tagged blocks and hierarchy

Tagged blocks may follow the gradient data:

| Signature | Length field | Support |
| --- | --- | --- |
| `8BIM` | `uint32` | Decoded and preserved |
| `8B64` | `uint64` | Decoded and preserved |

A `phry` block holds a versioned descriptor listing groups and presets, which GrdKit maps through PsCore's shared hierarchy mapper. Gradients carry no identifier, so presets resolve by position.

`GrdFile.hierarchy` exposes the flattened entries, `hierarchyDescriptors` retains the complete descriptors, and `groupPathOf(index)` returns a gradient's enclosing group names. A gradient without a matching hierarchy entry is treated as a top-level preset.

## Decoding modes and limits

`GrdDecodeMode.tolerant` is the default. It reports recoverable compatibility issues through `GrdFile.warnings`, including:

- descriptor-list entries that do not contain a gradient;
- unknown gradient forms or unsupported legacy color models;
- unknown tagged-block keys and unrecognized trailing bytes;
- malformed optional hierarchy data.

`GrdDecodeMode.strict` promotes compatibility issues to `GrdFormatException`. Tolerant mode does not recover a truncated main descriptor or invent missing legacy records.

Resource options bound the work performed by the decoder:

| Option | Controlled resource |
| --- | --- |
| `maxFileBytes` | Total input size |
| `maxGradients` | Declared gradient count |
| `maxStops` | Color or transparency stops in one legacy gradient |
| `descriptorOptions` | Action Descriptor depth, values, and payload limits |
| `maxHierarchyEntries` | Entries decoded by the hierarchy mapper |
| `maxTaggedBlockBytes` | Payload bytes in one tagged block |

Failures in the main gradient structure stop decoding. A failure while interpreting an optional `phry` descriptor can instead become a hierarchy warning in tolerant mode; callers should inspect warnings before relying on the group view.

## Preservation and encoding

`GrdEncoder` writes the current gradient descriptors into the root `GrdL` list and always emits a version 5 container with a version 16 descriptor. It does not reuse a complete source-file copy.

| Option | Effect |
| --- | --- |
| `GrdDecodeOptions.preserveTaggedBlockData` | Retains tagged-block payloads for later writing; enabled by default |
| `GrdEncodeOptions.includeTaggedBlocks` | Appends stored tagged blocks and their padding; enabled by default |
| `GrdEncodeOptions.includeTrailingData` | Appends unrecognized trailing bytes; enabled by default |

Keep tagged-block payloads when a decoded library must be written again with its hierarchy. The encoder writes preserved `phry` blocks unchanged; changing the typed hierarchy or reordering gradients does not rebuild those blocks. If source payloads were discarded, omit the corresponding blocks from output instead of expecting the semantic hierarchy to regenerate them.

Byte-exact reconstruction is possible for supported version 5 data with preserved extensions, as exercised by the bundled fixture. It is not guaranteed for every tolerant decode: invalid `GrdL` entries are skipped, descriptor versions are normalized, and legacy version 3 files are upgraded. Unknown keys inside retained descriptors remain available for re-encoding.

## Integration guidance

Use `PsGradient` for custom-stop or noise parameters and retain the full `GrdGradient.descriptor` when editing fields outside the typed view. `GrdGradient.withGradient` replaces the gradient while preserving its wrapper; `GrdFile.create` builds a new ungrouped library.

Rendering belongs to the application. Resolve foreground and background stops against the current document, choose an interpolation policy, and handle noise gradients from their stored parameters. `PsColor.toRgb()` supplies a profile-free preview conversion for supported process colors; it does not apply ICC profiles.

GrdKit has no Flutter dependency, so applications can decode large libraries outside their presentation layer or on a worker isolate.

## Validation corpus

The bundled `kiwi.grd` fixture comes from the MIT-licensed [`gradient`](https://github.com/zeevallin/gradient) Ruby gem. Tests check decoding without warnings and byte-exact re-encoding, alongside synthetic coverage for editing, hierarchy, legacy records, and malformed input.

The broader implementation corpus also recorded a successful round trip of `nine.grd`, with 3,397 gradients: 2,962 custom-stop and 435 noise gradients, including RGB, HSB, CMYK, grayscale, Lab, book colors, and dynamic stops. That larger file is not bundled with the package.

The inspector reports warnings and byte equality for individual local files:

```console
dart run tool/inspect_grd.dart gradients.grd
```

## References

- [Photoshop Gradients File Format](https://tonton-pixel.codeberg.page/photoshop-file-formats/gradients-file-format.html)
- [Gradient file formats](http://www.selapa.net/swatches/gradients/fileformats.php)
