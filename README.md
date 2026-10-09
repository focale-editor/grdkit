<p align="center">
  <img src="screenshots/overview.png" alt="GrdKit package illustration" width="180">
</p>

# GrdKit

GrdKit is a pure Dart codec for Adobe Photoshop gradient libraries (`.grd`). It reads current descriptor-based libraries and legacy version 3 libraries, writes version 5 libraries, and preserves data it does not interpret. It has no Flutter or native-code dependency, and builds on the shared Photoshop primitives of [`pscore`](https://pub.dev/packages/pscore).

The package is designed for editors such as Focale that need editable gradient presets, group paths, and access to complete Photoshop Action Descriptors.

## Supported data

- `8BGR` version 5 libraries: a version 16 Action Descriptor holding the `GrdL` gradient list.
- Custom-stop gradients (`CstS`) with color stops, transparency stops, midpoints, and smoothness.
- Color-noise gradients (`ClNs`) with their seed, roughness, color model, and channel ranges.
- RGB, CMYK, grayscale, HSB, Lab, and color-book stop colors, plus foreground and background stops.
- Legacy `8BGR` version 3 libraries, converted to the same descriptor model.
- Trailing tagged blocks, including `phry` group hierarchies, and unrecognized trailing bytes.
- Configurable limits for file size, gradients, legacy stops, descriptors, hierarchy entries, and tagged blocks.

The complete descriptors remain accessible alongside the typed gradient views. Unknown descriptor keys are retained; exact reconstruction depends on the input structure and the preservation options described in [docs/GRD.md](docs/GRD.md).

## Reading a file

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:grdkit/grdkit.dart';

final Uint8List bytes = await File('gradients.grd').readAsBytes();
final GrdFile library = GrdDecoder.decode(bytes);

for (int index = 0; index < library.gradients.length; index++) {
  final PsGradient gradient = library.gradients[index].gradient;
  print('${gradient.name}: ${gradient.colorStops.length} color stops');
  print('  groups: ${library.groupPathOf(index).join(' / ')}');
}
```

`GrdGradient.gradient` exposes a shared `PsGradient` view. Use `GrdGradient.descriptor` for the complete wrapper or `GrdFile.rootDescriptor` for library-level fields.

## Writing and editing

```dart
final GrdFile created = GrdFile.create([
  PsGradient.custom(
    name: 'Sunset',
    colorStops: [
      PsGradientColorStop.create(
        color: PsColor.rgb(red: 255, green: 94, blue: 0),
        location: 0,
      ),
      PsGradientColorStop.create(
        color: PsColor.rgb(red: 90, green: 0, blue: 160),
        location: 4096,
      ),
    ],
  ),
]);

final Uint8List output = GrdEncoder.encode(created);
await File('sunset.grd').writeAsBytes(output, flush: true);
```

Encoding always produces a version 5 library, including when the input used the legacy version 3 layout. `GrdGradient.withGradient` replaces a gradient while retaining the surrounding descriptor fields. `GrdFile.create` authors a new library without a group hierarchy.

`GrdEncodeOptions.includeTaggedBlocks` and `includeTrailingData` control whether preserved trailer data is written; both default to `true`.

## Reusable `dart:convert` API

`GrdCodec` implements `Codec<GrdFile, List<int>>` and keeps decoding and encoding policies together in one immutable value:

```dart
const GrdCodec codec = GrdCodec(
  decodeOptions: GrdDecodeOptions(mode: GrdDecodeMode.strict),
  encodeOptions: GrdEncodeOptions(),
);

final GrdFile library = codec.decode(bytes);
final Uint8List encoded = codec.encode(library);
```

The `List<int>` binary type allows composition with standard codecs such as `base64`; direct `encode` calls still return `Uint8List`. `GrdEncoder` and `GrdDecoder` are also configurable `Converter` implementations. Every conversion consumes or produces one complete in-memory GRD file rather than an incremental byte stream.

## Hierarchy

Newer libraries can append a `phry` group hierarchy. `GrdFile.hierarchy` exposes its ordered group and preset entries, while `groupPathOf(index)` returns the enclosing group names for one gradient. Gradients without a hierarchy entry remain at the top level.

The complete hierarchy descriptors remain available in `hierarchyDescriptors`. Preserved `phry` blocks are written back unchanged; editing the typed hierarchy does not regenerate those blocks.

## Strict, tolerant, and bounded decoding

`GrdDecodeMode.tolerant`, the default, records recoverable problems in `GrdFile.warnings`: unknown tagged blocks, trailing bytes, list entries holding no gradient, unknown gradient forms, and unsupported legacy color models. `GrdDecodeMode.strict` turns each of them into a `GrdFormatException`. Structural damage, such as a bad signature or a truncated descriptor, always throws.

```dart
final GrdFile library = GrdDecoder.decode(
  bytes,
  options: const GrdDecodeOptions(mode: GrdDecodeMode.strict),
);
```

Decode options bound input size, gradient and legacy-stop counts, descriptor complexity, hierarchy entries, and tagged-block payloads. Keep `preserveTaggedBlockData` enabled when the library must be saved with its original trailer blocks.

The bundled inspector accepts individual files, prints gradients and warnings, and compares re-encoded bytes with the source:

```console
dart run tool/inspect_grd.dart gradients.grd
```

## Current boundaries

GrdKit does not render gradients. Noise gradients are exposed as their parameters only, and dynamic foreground or background stops are left for the caller to resolve. `PsColor.toRgb()` provides a profile-free approximation of supported process colors for previews; color-managed rendering belongs to the application.

See [docs/GRD.md](docs/GRD.md) for the binary layout, descriptor mapping, preservation rules, and integration guidance.

## References

- [Photoshop Gradients File Format](https://tonton-pixel.codeberg.page/photoshop-file-formats/gradients-file-format.html)
- [Gradient file formats](http://www.selapa.net/swatches/gradients/fileformats.php)

GrdKit is an independent implementation and is not affiliated with or endorsed by Adobe.

---

Built for **[Focale](https://focale-editor.app)**, an advanced local image editor. Discover what these packages make possible in a real creative workflow.
