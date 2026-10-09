import 'dart:convert';
import 'dart:typed_data';

import 'package:grdkit/src/model/grd_file.dart';
import 'package:grdkit/src/model/grd_gradient.dart';
import 'package:grdkit/src/model/grd_options.dart';
import 'package:pscore/pscore.dart';

/// Decodes Adobe Photoshop `8BGR` gradient libraries.
///
/// Version 5 libraries store an Action Descriptor, optionally followed by
/// tagged blocks such as the `phry` group hierarchy. Legacy version 3
/// libraries use a fixed binary layout and are converted to the same
/// descriptor model.
///
/// The configured instance is a one-shot [Converter] for complete in-memory
/// files. Use [decode] when conversion options are supplied per call.
final class GrdDecoder extends Converter<List<int>, GrdFile> {
  /// Options applied by [convert].
  final GrdDecodeOptions options;

  /// Creates a reusable decoder with fixed [options].
  const GrdDecoder({
    this.options = const GrdDecodeOptions(),
  });

  @override
  GrdFile convert(List<int> input) => decode(
    input is Uint8List ? input : Uint8List.fromList(input),
    options: options,
  );

  /// Four-byte file signature used by every gradient library.
  static const String _fileSignature = '8BGR';

  /// Descriptor version stored before a Photoshop Action Descriptor.
  static const int _descriptorVersion = 16;

  /// Decodes one complete in-memory GRD [bytes] buffer.
  static GrdFile decode(
    Uint8List bytes, {
    GrdDecodeOptions options = const GrdDecodeOptions(),
  }) {
    if (bytes.length > options.maxFileBytes) {
      throw GrdFormatException(
        message: 'GRD file size ${bytes.length} exceeds the configured ${options.maxFileBytes} byte limit',
        source: bytes,
        offset: 0,
      );
    }
    try {
      final PsBinaryReader reader = PsBinaryReader(bytes: bytes);
      final String signature = reader.readString(4);
      if (signature != _fileSignature) {
        throw PsFormatException(message: 'Invalid GRD signature "$signature"; expected "$_fileSignature"', source: bytes, offset: 0);
      }
      final int version = reader.readUint16();
      final _GrdDecodeContext context = _GrdDecodeContext(source: bytes, options: options, version: version);
      switch (version) {
        case 5:
          _decodeDescriptorLibrary(reader, context);
        case 3:
          _decodeLegacyLibrary(reader, context);
        default:
          throw PsFormatException(message: 'Unsupported GRD version $version', source: bytes, offset: 4);
      }
      _decodeTaggedBlocks(reader, context);
      return context.build();
    } on GrdFormatException {
      rethrow;
    } on PsFormatException catch (error) {
      throw GrdFormatException(message: error.message, source: bytes, offset: error.offset);
    } on RangeError catch (error) {
      throw GrdFormatException(message: 'Invalid GRD numeric range: $error', source: bytes);
    }
  }

  /// Decodes the versioned descriptor of a version 5 library.
  static void _decodeDescriptorLibrary(PsBinaryReader reader, _GrdDecodeContext context) {
    final int descriptorOffset = reader.offset;
    final PsVersionedDescriptor versioned = PsVersionedDescriptorCodec.read(reader, options: context.options.descriptorOptions);
    if (versioned.version != _descriptorVersion) {
      context.issue('GRD descriptor version ${versioned.version} is not currently defined', descriptorOffset);
    }
    context.rootDescriptor = versioned.descriptor;
    final List<PsDescriptorValue>? entries = versioned.descriptor.listValue('GrdL');
    if (entries == null) {
      throw PsFormatException(message: 'The GRD descriptor has no GrdL gradient list', source: context.source, offset: descriptorOffset);
    }
    context.checkGradientCount(entries.length, descriptorOffset);
    for (int index = 0; index < entries.length; index++) {
      context.gradientIndex = index;
      final PsDescriptor? descriptor = entries[index].asObject();
      final GrdGradient? gradient = descriptor == null ? null : GrdGradient.tryFromDescriptor(descriptor);
      if (gradient == null) {
        context.issue('GRD list entry ${index + 1} does not hold a gradient object', descriptorOffset);
        continue;
      }
      if (gradient.gradient.form == PsGradientForm.unknown) {
        context.issue('Gradient form "${gradient.gradient.formIdentifier}" is not recognized', descriptorOffset);
      }
      context.gradients.add(gradient);
    }
    context.gradientIndex = null;
  }

  /// Decodes the fixed binary records of a version 3 library.
  static void _decodeLegacyLibrary(PsBinaryReader reader, _GrdDecodeContext context) {
    final int count = reader.readUint16();
    context.checkGradientCount(count, 6);
    for (int index = 0; index < count; index++) {
      context.gradientIndex = index;
      final int recordOffset = reader.offset;
      final String name = latin1.decode(reader.readBytes(reader.readUint8()));
      final int colorCount = reader.readUint16();
      context.checkStopCount(colorCount, recordOffset);
      final List<PsGradientColorStop> colorStops = [];
      for (int stop = 0; stop < colorCount; stop++) {
        final int stopOffset = reader.offset;
        final int location = reader.readInt32();
        final int midpoint = reader.readInt32();
        final int model = reader.readUint16();
        final List<int> components = [for (int component = 0; component < 4; component++) reader.readUint16()];
        final int type = reader.readUint16();
        final PsColor? color = _legacyColor(model, components);
        if (color == null) {
          context.issue('Legacy color model $model is not supported', stopOffset);
        }
        colorStops.add(_legacyColorStop(location: location, midpoint: midpoint, type: type, color: color));
      }
      final int transparencyCount = reader.readUint16();
      context.checkStopCount(transparencyCount, recordOffset);
      final List<PsGradientTransparencyStop> transparencyStops = [
        for (int stop = 0; stop < transparencyCount; stop++) PsGradientTransparencyStop.create(location: reader.readInt32(), midpoint: reader.readInt32(), opacity: reader.readUint16() / 255 * 100),
      ];
      reader.skip(6);
      context.gradients.add(
        GrdGradient.create(PsGradient.custom(name: name, colorStops: colorStops, transparencyStops: transparencyStops)),
      );
    }
    context.gradientIndex = null;
    context.rootDescriptor = PsDescriptor(
      name: '',
      classId: 'null',
      items: [
        PsDescriptorItem(
          key: 'GrdL',
          value: PsListValue(values: [for (final GrdGradient gradient in context.gradients) PsObjectValue(value: gradient.descriptor)]),
        ),
      ],
    );
  }

  /// Creates a stop from one legacy record, keeping dynamic stop kinds.
  static PsGradientColorStop _legacyColorStop({required int location, required int midpoint, required int type, required PsColor? color}) {
    final String kind = switch (type) {
      1 => 'FrgC',
      2 => 'BckC',
      _ => 'UsrS',
    };
    return PsGradientColorStop.fromDescriptor(
      PsDescriptor(
        name: '\u0000',
        classId: 'Clrt',
        items: [
          if (kind == 'UsrS' && color != null)
            PsDescriptorItem(
              key: 'Clr ',
              value: PsObjectValue(value: color.descriptor),
            ),
          PsDescriptorItem(
            key: 'Type',
            value: PsEnumeratedValue(typeId: 'Clry', value: kind),
          ),
          PsDescriptorItem(
            key: 'Lctn',
            value: PsIntegerValue(value: location),
          ),
          PsDescriptorItem(
            key: 'Mdpn',
            value: PsIntegerValue(value: midpoint),
          ),
        ],
      ),
    );
  }

  /// Converts one legacy color record, using the conventions of Photoshop color structures.
  static PsColor? _legacyColor(int model, List<int> components) => switch (model) {
    0 => PsColor.rgb(red: components[0] / 257, green: components[1] / 257, blue: components[2] / 257),
    1 => PsColor.hsb(hue: components[0] / 65535 * 360, saturation: components[1] / 655.35, brightness: components[2] / 655.35),
    2 => PsColor.cmyk(
      cyan: 100 - components[0] / 655.35,
      magenta: 100 - components[1] / 655.35,
      yellow: 100 - components[2] / 655.35,
      black: 100 - components[3] / 655.35,
    ),
    7 => PsColor.lab(lightness: components[0] / 100, a: components[1].toSigned(16) / 100, b: components[2].toSigned(16) / 100),
    8 => PsColor.grayscale(gray: 100 - components[0] / 100),
    _ => null,
  };

  /// Decodes recognizable length-prefixed blocks after the gradients.
  static void _decodeTaggedBlocks(PsBinaryReader reader, _GrdDecodeContext context) {
    while (!reader.isAtEnd) {
      final int blockOffset = reader.baseOffset + reader.offset;
      if (reader.remaining < 12 || !PsTaggedBlockCodec.hasSignature(reader)) {
        context.trailingData = reader.readBytes(reader.remaining);
        context.issue('${context.trailingData.length} unrecognized trailing bytes remain after the GRD payload', blockOffset);
        return;
      }
      final PsTaggedBlockHeader header = PsTaggedBlockCodec.readHeader(reader, maxPayloadBytes: context.options.maxTaggedBlockBytes);
      context.blockKey = header.key;
      if (header.declaredLength > reader.remaining) {
        throw PsFormatException(
          message: 'GRD tagged block ${header.key} length ${header.declaredLength} exceeds the ${reader.remaining} available bytes',
          source: context.source,
          offset: blockOffset + 8,
        );
      }
      final Uint8List payload = reader.readView(header.declaredLength);
      final Uint8List padding = reader.readBytes(PsTaggedBlockCodec.paddingLength(reader, payloadLength: header.declaredLength));
      context.taggedBlocks.add(
        PsTaggedBlock(
          signature: header.signature,
          key: header.key,
          offset: blockOffset,
          declaredLength: header.declaredLength,
          data: context.options.preserveTaggedBlockData ? payload : Uint8List(0),
          paddingData: padding,
        ),
      );
      if (header.key == 'phry') {
        _decodeHierarchyBlock(payload: payload, payloadOffset: header.payloadOffset, context: context);
      } else {
        context.issue('Unknown GRD tagged block ${header.key} was preserved', blockOffset + 4);
      }
      context.blockKey = null;
    }
  }

  /// Decodes the versioned Action Descriptor inside a `phry` payload.
  static void _decodeHierarchyBlock({
    required Uint8List payload,
    required int payloadOffset,
    required _GrdDecodeContext context,
  }) {
    try {
      final PsBinaryReader reader = PsBinaryReader(bytes: payload, baseOffset: payloadOffset);
      final PsDescriptor descriptor = PsVersionedDescriptorCodec.read(reader, options: context.options.descriptorOptions).descriptor;
      if (!reader.isAtEnd) {
        context.issue('${reader.remaining} extension bytes remain after the GRD hierarchy descriptor', reader.baseOffset + reader.offset);
      }
      context.hierarchyDescriptors.add(descriptor);
      final int indexOffset = context.hierarchy.length;
      for (final PsPresetHierarchyEntry entry in PsPresetHierarchyMapper.decode(
        root: descriptor,
        presets: [for (final GrdGradient gradient in context.gradients) PsPresetIdentity(name: gradient.name, id: null)],
        maxEntries: context.options.maxHierarchyEntries,
        onIssue: (message) => context.issue(message, payloadOffset),
        formatLabel: 'GRD',
        presetLabel: 'a decoded gradient',
      )) {
        context.hierarchy.add(
          PsPresetHierarchyEntry(
            index: entry.index + indexOffset,
            kind: entry.kind,
            depth: entry.depth,
            classId: entry.classId,
            name: entry.name,
            id: entry.id,
            presetIndex: entry.presetIndex,
            rawDescriptor: entry.rawDescriptor,
          ),
        );
      }
    } on PsFormatException catch (error) {
      if (context.options.mode == GrdDecodeMode.strict) {
        rethrow;
      }
      context.warning('GRD hierarchy could not be decoded: ${error.message}', error.offset ?? payloadOffset);
    }
  }
}

/// Accumulates immutable GRD models and source-aware compatibility warnings.
final class _GrdDecodeContext {
  /// Complete input used as an exception source.
  final Uint8List source;

  /// Caller-selected limits and compatibility behavior.
  final GrdDecodeOptions options;

  /// GRD container version.
  final int version;

  /// Decoded gradients.
  final List<GrdGradient> gradients = [];

  /// Flattened typed hierarchy entries.
  final List<PsPresetHierarchyEntry> hierarchy = [];

  /// Decoded source hierarchy descriptors.
  final List<PsDescriptor> hierarchyDescriptors = [];

  /// Preserved tagged blocks.
  final List<PsTaggedBlock> taggedBlocks = [];

  /// Collected tolerant-mode warnings.
  final List<GrdWarning> warnings = [];

  /// Root descriptor holding the gradient list.
  PsDescriptor? rootDescriptor;

  /// Bytes that could not be assigned to a recognized structure.
  Uint8List trailingData = Uint8List(0);

  /// Gradient currently being decoded, when applicable.
  int? gradientIndex;

  /// Tagged block currently being decoded, when applicable.
  String? blockKey;

  /// Creates an empty decode accumulator.
  _GrdDecodeContext({
    required this.source,
    required this.options,
    required this.version,
  });

  /// Rejects a gradient count above the configured limit.
  void checkGradientCount(int count, int offset) {
    if (count > options.maxGradients) {
      throw PsFormatException(message: 'GRD gradient count $count exceeds the configured ${options.maxGradients} limit', source: source, offset: offset);
    }
  }

  /// Rejects a legacy stop count above the configured limit.
  void checkStopCount(int count, int offset) {
    if (count > options.maxStops) {
      throw PsFormatException(message: 'GRD stop count $count exceeds the configured ${options.maxStops} limit', source: source, offset: offset);
    }
  }

  /// Promotes a compatibility issue in strict mode or records a warning.
  void issue(String message, int offset) {
    if (options.mode == GrdDecodeMode.strict) {
      throw PsFormatException(message: message, source: source, offset: offset);
    }
    warning(message, offset);
  }

  /// Records a warning without applying the strict-mode promotion policy.
  void warning(String message, int offset) {
    warnings.add(GrdWarning(message: message, offset: offset, gradientIndex: gradientIndex, blockKey: blockKey));
  }

  /// Builds the immutable public result.
  GrdFile build() => GrdFile(
    version: version,
    gradients: gradients,
    rootDescriptor: rootDescriptor,
    hierarchy: hierarchy,
    hierarchyDescriptors: hierarchyDescriptors,
    taggedBlocks: taggedBlocks,
    trailingData: trailingData,
    warnings: warnings,
  );
}
