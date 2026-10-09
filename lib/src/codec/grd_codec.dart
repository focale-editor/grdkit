import 'dart:convert';
import 'dart:typed_data';

import 'package:grdkit/src/codec/grd_decoder.dart';
import 'package:grdkit/src/codec/grd_encoder.dart';
import 'package:grdkit/src/model/grd_file.dart';
import 'package:grdkit/src/model/grd_options.dart';

/// Converts GRD models to and from their binary representation.
///
/// Each conversion handles one complete in-memory file. The encoded type is
/// [List<int>] so this codec can be composed with standard `dart:convert`
/// codecs, while [encode] keeps the more precise [Uint8List] return type.
final class GrdCodec extends Codec<GrdFile, List<int>> {
  /// Options applied while decoding.
  final GrdDecodeOptions decodeOptions;

  /// Options applied while encoding.
  final GrdEncodeOptions encodeOptions;

  /// Creates a reusable codec with fixed decoding and encoding options.
  const GrdCodec({
    this.decodeOptions = const GrdDecodeOptions(),
    this.encodeOptions = const GrdEncodeOptions(),
  });

  @override
  GrdDecoder get decoder => GrdDecoder(options: decodeOptions);

  @override
  GrdEncoder get encoder => GrdEncoder(options: encodeOptions);

  @override
  Uint8List encode(GrdFile input) => encoder.convert(input);
}
