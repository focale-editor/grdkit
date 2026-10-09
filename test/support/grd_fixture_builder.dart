import 'dart:convert';
import 'dart:typed_data';

import 'package:grdkit/grdkit.dart';

/// One legacy color stop written by [legacyLibrary].
typedef LegacyColorStop = ({int location, int midpoint, int model, List<int> components, int type});

/// One legacy transparency stop written by [legacyLibrary].
typedef LegacyTransparencyStop = ({int location, int midpoint, int opacity});

/// Builds a version 3 library holding one gradient per entry of [gradients].
Uint8List legacyLibrary(List<({String name, List<LegacyColorStop> colors, List<LegacyTransparencyStop> opacities})> gradients) {
  final PsBinaryWriter writer = PsBinaryWriter()
    ..writeString('8BGR')
    ..writeUint16(3)
    ..writeUint16(gradients.length);
  for (final gradient in gradients) {
    final List<int> name = latin1.encode(gradient.name);
    writer
      ..writeUint8(name.length)
      ..writeBytes(name)
      ..writeUint16(gradient.colors.length);
    for (final LegacyColorStop stop in gradient.colors) {
      writer
        ..writeInt32(stop.location)
        ..writeInt32(stop.midpoint)
        ..writeUint16(stop.model)
        ..writeUint16List(stop.components)
        ..writeUint16(stop.type);
    }
    writer.writeUint16(gradient.opacities.length);
    for (final LegacyTransparencyStop stop in gradient.opacities) {
      writer
        ..writeInt32(stop.location)
        ..writeInt32(stop.midpoint)
        ..writeUint16(stop.opacity);
    }
    writer.writeZeros(6);
  }
  return writer.takeBytes();
}

/// Creates a `phry` block placing the gradients named in [layout] inside groups.
///
/// A string starting with `>` opens a group, `<` closes one, and any other
/// string refers to a gradient by name.
PsTaggedBlock hierarchyBlock(List<String> layout) => PsTaggedBlock(
  signature: '8BIM',
  key: 'phry',
  data: PsVersionedDescriptorCodec.encode(
    PsVersionedDescriptor(
      descriptor: PsDescriptor(
        name: '',
        classId: 'null',
        items: [
          PsDescriptorItem(
            key: 'hierarchy',
            value: PsListValue(
              values: [
                for (final String item in layout)
                  PsObjectValue(
                    value: switch (item[0]) {
                      '>' => PsDescriptor(
                        name: '',
                        classId: 'Grup',
                        items: [
                          PsDescriptorItem(
                            key: 'Nm  ',
                            value: PsStringValue(value: '${item.substring(1)}\u0000'),
                          ),
                        ],
                      ),
                      '<' => const PsDescriptor(name: '', classId: 'groupEnd'),
                      _ => PsDescriptor(
                        name: '',
                        classId: 'preset',
                        items: [
                          PsDescriptorItem(
                            key: 'Nm  ',
                            value: PsStringValue(value: '$item\u0000'),
                          ),
                        ],
                      ),
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  ),
);
