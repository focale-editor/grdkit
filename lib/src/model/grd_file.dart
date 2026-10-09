import 'dart:typed_data';

import 'package:grdkit/src/model/grd_gradient.dart';
import 'package:grdkit/src/model/grd_options.dart';
import 'package:pscore/pscore.dart';

/// Complete decoded contents of one Adobe Photoshop gradient library.
final class GrdFile {
  /// Container version read from the file: 3 for legacy libraries, otherwise 5.
  ///
  /// Encoding always writes version 5.
  final int version;

  /// Gradients in source order.
  final List<GrdGradient> gradients;

  /// Root descriptor holding the `GrdL` list, synthesized for legacy files.
  final PsDescriptor rootDescriptor;

  /// Flattened group and preset hierarchy from all recognized `phry` blocks.
  final List<PsPresetHierarchyEntry> hierarchy;

  /// Complete root descriptors from every recognized `phry` block.
  final List<PsDescriptor> hierarchyDescriptors;

  /// Every trailing tagged block, including unknown forward-compatible keys.
  final List<PsTaggedBlock> taggedBlocks;

  /// Bytes following the last recognized structure.
  final Uint8List trailingData;

  /// Recoverable compatibility issues encountered while decoding.
  final List<GrdWarning> warnings;

  /// Creates an immutable decoded GRD library.
  GrdFile({
    this.version = 5,
    required List<GrdGradient> gradients,
    PsDescriptor? rootDescriptor,
    List<PsPresetHierarchyEntry> hierarchy = const [],
    List<PsDescriptor> hierarchyDescriptors = const [],
    List<PsTaggedBlock> taggedBlocks = const [],
    Uint8List? trailingData,
    List<GrdWarning> warnings = const [],
  }) : gradients = List<GrdGradient>.unmodifiable(gradients),
       rootDescriptor = rootDescriptor ?? const PsDescriptor(name: '', classId: 'null'),
       hierarchy = List<PsPresetHierarchyEntry>.unmodifiable(hierarchy),
       hierarchyDescriptors = List<PsDescriptor>.unmodifiable(hierarchyDescriptors),
       taggedBlocks = List<PsTaggedBlock>.unmodifiable(taggedBlocks),
       trailingData = Uint8List.fromList(trailingData ?? Uint8List(0)).asUnmodifiableView(),
       warnings = List<GrdWarning>.unmodifiable(warnings);

  /// Creates a new library holding [gradients] without any hierarchy.
  factory GrdFile.create(List<PsGradient> gradients) => GrdFile(gradients: [for (final PsGradient gradient in gradients) GrdGradient.create(gradient)]);

  /// Returns the names of the groups enclosing the gradient at [index].
  ///
  /// Gradients the hierarchy does not mention are reported at the top level.
  List<String> groupPathOf(int index) {
    final List<String> groups = [];
    for (final PsPresetHierarchyEntry entry in hierarchy) {
      switch (entry.kind) {
        case PsPresetHierarchyEntryKind.groupStart:
          groups.add(entry.name ?? '');
        case PsPresetHierarchyEntryKind.groupEnd:
          if (groups.isNotEmpty) {
            groups.removeLast();
          }
        case PsPresetHierarchyEntryKind.preset when entry.presetIndex == index:
          return List<String>.unmodifiable(groups);
        case PsPresetHierarchyEntryKind.preset || PsPresetHierarchyEntryKind.empty || PsPresetHierarchyEntryKind.unknown:
          break;
      }
    }
    return const [];
  }
}
