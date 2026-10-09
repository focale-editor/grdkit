import 'dart:io';
import 'dart:typed_data';

import 'package:grdkit/grdkit.dart';

/// Prints the gradients and groups of one GRD library.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run example/main.dart <library.grd>');
    exitCode = 64;
    return;
  }
  final Uint8List bytes = await File(arguments.single).readAsBytes();
  final GrdFile library = GrdDecoder.decode(bytes);
  for (int index = 0; index < library.gradients.length; index++) {
    final PsGradient gradient = library.gradients[index].gradient;
    final List<String> groups = library.groupPathOf(index);
    stdout.writeln('${[...groups, gradient.name ?? ''].join(' / ')}: ${gradient.form.name}, ${gradient.colorStops.length} color stops');
  }
  library.warnings.forEach(stderr.writeln);
}
