import 'dart:convert';
import 'dart:typed_data';

import 'package:grdkit/src/model/grd_file.dart';
import 'package:grdkit/src/model/grd_gradient.dart';
import 'package:grdkit/src/model/grd_options.dart';
import 'package:pscore/pscore.dart';

/// Encodes Adobe Photoshop gradient libraries in the version 5 layout.
///
/// Legacy version 3 libraries are upgraded: their gradients are written as
/// descriptors, which every Photoshop release since 6.0 reads.
final class GrdEncoder extends Converter<GrdFile, List<int>> {
  /// Options applied by [convert].
  final GrdEncodeOptions options;

  /// Creates a reusable encoder with fixed [options].
  const GrdEncoder({
    this.options = const GrdEncodeOptions(),
  });

  @override
  Uint8List convert(GrdFile input) => encode(input, options: options);

  /// Encodes [file] into a complete GRD library.
  static Uint8List encode(
    GrdFile file, {
    GrdEncodeOptions options = const GrdEncodeOptions(),
  }) {
    try {
      final PsBinaryWriter writer = PsBinaryWriter()
        ..writeString('8BGR')
        ..writeUint16(5);
      PsVersionedDescriptorCodec.write(
        writer,
        PsVersionedDescriptor(
          descriptor: file.rootDescriptor.withValue(
            'GrdL',
            PsListValue(values: [for (final GrdGradient gradient in file.gradients) PsObjectValue(value: gradient.descriptor)]),
          ),
        ),
      );
      if (options.includeTaggedBlocks) {
        for (final PsTaggedBlock block in file.taggedBlocks) {
          PsTaggedBlockCodec.write(writer, block, preservePadding: true);
        }
      }
      if (options.includeTrailingData) {
        writer.writeBytes(file.trailingData);
      }
      return writer.takeBytes();
    } on GrdWriteException {
      rethrow;
    } on PsWriteException catch (error) {
      throw GrdWriteException(message: error.message);
    }
  }
}
