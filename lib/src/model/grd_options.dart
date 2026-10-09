import 'package:pscore/pscore.dart';

/// Controls whether recoverable GRD compatibility issues stop decoding.
enum GrdDecodeMode {
  /// Rejects unknown extensions and malformed optional data.
  strict,

  /// Preserves unknown data and reports recoverable defects as warnings.
  tolerant,
}

/// Resource and preservation limits applied while decoding a GRD library.
final class GrdDecodeOptions {
  /// Handling policy for recoverable format extensions and damaged records.
  final GrdDecodeMode mode;

  /// Maximum accepted input size.
  final int maxFileBytes;

  /// Maximum number of gradients declared by one library.
  final int maxGradients;

  /// Maximum number of color or transparency stops in one legacy gradient.
  final int maxStops;

  /// Maximum payload length accepted for one trailing tagged block.
  final int maxTaggedBlockBytes;

  /// Maximum number of hierarchy entries exposed from `phry` descriptors.
  final int maxHierarchyEntries;

  /// Resource limits applied to every Action Descriptor.
  final PsDescriptorDecodeOptions descriptorOptions;

  /// Whether tagged trailer blocks retain their complete payload bytes.
  final bool preserveTaggedBlockData;

  /// Creates bounded decode options suitable for untrusted input.
  const GrdDecodeOptions({
    this.mode = GrdDecodeMode.tolerant,
    this.maxFileBytes = 256 * 1024 * 1024,
    this.maxGradients = 100000,
    this.maxStops = 4096,
    this.maxTaggedBlockBytes = 64 * 1024 * 1024,
    this.maxHierarchyEntries = 100000,
    this.descriptorOptions = const PsDescriptorDecodeOptions(),
    this.preserveTaggedBlockData = true,
  });
}

/// Preservation choices applied while encoding a GRD library.
final class GrdEncodeOptions {
  /// Whether trailing Photoshop tagged blocks are appended.
  final bool includeTaggedBlocks;

  /// Whether uninterpreted bytes after the tagged blocks are appended.
  final bool includeTrailingData;

  /// Creates encoding options that keep preserved data by default.
  const GrdEncodeOptions({
    this.includeTaggedBlocks = true,
    this.includeTrailingData = true,
  });
}

/// Describes a recoverable compatibility issue found while decoding.
final class GrdWarning extends PsWarning {
  /// Zero-based gradient index associated with the issue, when known.
  final int? gradientIndex;

  /// Tagged-block key associated with the issue, when known.
  final String? blockKey;

  /// Creates a warning with optional source context.
  const GrdWarning({
    required super.message,
    super.offset,
    this.gradientIndex,
    this.blockKey,
  });

  @override
  String get typeName => 'GrdWarning';

  @override
  String get context {
    final int? currentGradientIndex = gradientIndex;
    final String gradient = currentGradientIndex == null ? '' : ' in gradient ${currentGradientIndex + 1}';
    final String block = blockKey == null ? '' : ' in $blockKey';
    return '$gradient$block';
  }
}

/// Reports malformed, truncated, unsupported, or unsafe GRD input.
final class GrdFormatException extends PsFormatException {
  /// Creates an error at an optional absolute byte [offset].
  const GrdFormatException({
    required super.message,
    super.source,
    super.offset,
  });

  @override
  String get typeName => 'GrdFormatException';
}

/// Reports model data that cannot be represented by a GRD library.
final class GrdWriteException extends PsWriteException {
  /// Creates an encoding error with a user-facing [message].
  const GrdWriteException({
    required super.message,
  });

  @override
  String get typeName => 'GrdWriteException';
}
