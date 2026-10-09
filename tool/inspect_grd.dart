import 'dart:io';
import 'dart:typed_data';

import 'package:grdkit/grdkit.dart';

/// Prints the gradients of GRD libraries and checks that each re-encodes identically.
Future<void> main(List<String> arguments) async {
  for (final String path in arguments) {
    final Uint8List bytes = await File(path).readAsBytes();
    final GrdFile file = GrdDecoder.decode(bytes);
    final Uint8List encoded = GrdEncoder.encode(file);
    final bool identical = encoded.length == bytes.length && Iterable<int>.generate(bytes.length).every((index) => bytes[index] == encoded[index]);
    stdout.writeln('$path: version ${file.version}, ${file.gradients.length} gradients, ${file.taggedBlocks.length} blocks, ${file.warnings.length} warnings, identical: $identical');
    for (int index = 0; index < file.gradients.length && index < 12; index++) {
      final PsGradient gradient = file.gradients[index].gradient;
      stdout.writeln('  ${gradient.name} [${gradient.form.name}] ${gradient.colorStops.length} colors, ${gradient.transparencyStops.length} opacities, groups ${file.groupPathOf(index)}');
    }
    file.warnings.take(5).forEach(stdout.writeln);
  }
}
