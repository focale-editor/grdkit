import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:checks/checks.dart';
import 'package:grdkit/grdkit.dart';
import 'package:test/test.dart';

import 'support/grd_fixture_builder.dart';

/// Exercises GRD decoding, encoding, and the legacy layout.
void main() {
  group('Photoshop library', () {
    test('decodes the kiwi fixture and re-encodes it identically', () {
      final Uint8List bytes = _fixture('kiwi.grd');
      final GrdFile file = GrdDecoder.decode(bytes);
      final PsGradient gradient = file.gradients.single.gradient;

      check(file.version).equals(5);
      check(file.warnings).isEmpty();
      check(gradient.name).equals('Kiwi');
      check(gradient.form).equals(PsGradientForm.customStops);
      check(gradient.colorStops).length.equals(5);
      check(gradient.transparencyStops).length.equals(2);
      check(gradient.colorStops.first.color?.toRgb()).isNotNull();
      check(const GrdCodec().encode(file)).deepEquals(bytes);
    });
  });

  group('authored libraries', () {
    test('round-trips new custom-stop gradients', () {
      final GrdFile file = GrdFile.create([
        PsGradient.custom(
          name: 'Sunset',
          colorStops: [
            PsGradientColorStop.create(color: PsColor.rgb(red: 255, green: 64, blue: 0), location: 0),
            PsGradientColorStop.create(color: PsColor.cmyk(cyan: 100, magenta: 0, yellow: 0, black: 0), location: 4096, midpoint: 30),
          ],
          transparencyStops: [PsGradientTransparencyStop.create(opacity: 40, location: 2048)],
        ),
      ]);

      final GrdFile decoded = const GrdCodec().decode(const GrdCodec().encode(file));
      final PsGradient gradient = decoded.gradients.single.gradient;

      check(decoded.warnings).isEmpty();
      check(decoded.gradients.single.descriptor.classId).equals('Grdn');
      check(gradient.name).equals('Sunset');
      check(gradient.colorStops.last.midpoint).equals(30);
      check(gradient.colorStops.last.color?.colorSpace).equals(PsColorSpace.cmyk);
      check(gradient.transparencyStops.single.opacity?.value).equals(40);
    });

    test('replaces a wrapped gradient while keeping its wrapper', () {
      final GrdGradient entry = GrdGradient.create(PsGradient.custom(name: 'A', colorStops: const []));
      final GrdGradient renamed = entry.withGradient(PsGradient.custom(name: 'B', colorStops: const []));

      check(renamed.descriptor.name).equals(entry.descriptor.name);
      check(renamed.name).equals('B');
      check(GrdGradient.tryFromDescriptor(renamed.descriptor)?.name).equals('B');
    });
  });

  group('hierarchy', () {
    test('maps phry groups to gradient group paths', () {
      final GrdFile source = GrdFile(
        gradients: [
          for (final String name in ['Loose', 'Warm', 'Cold']) GrdGradient.create(PsGradient.custom(name: name, colorStops: const [])),
        ],
        taggedBlocks: [
          hierarchyBlock(['Loose', '>Tones', 'Warm', '>Deep', 'Cold', '<', '<']),
        ],
      );

      final Uint8List bytes = GrdEncoder.encode(source);
      final GrdFile decoded = GrdDecoder.decode(bytes, options: const GrdDecodeOptions(mode: GrdDecodeMode.strict));

      check(decoded.hierarchyDescriptors).length.equals(1);
      check(decoded.groupPathOf(0)).isEmpty();
      check(decoded.groupPathOf(1)).deepEquals(['Tones']);
      check(decoded.groupPathOf(2)).deepEquals(['Tones', 'Deep']);
      check(GrdEncoder.encode(decoded)).deepEquals(bytes);
      check(GrdEncoder.encode(decoded, options: const GrdEncodeOptions(includeTaggedBlocks: false)).length).isLessThan(bytes.length);
    });
  });

  group('legacy version 3', () {
    test('converts colors, dynamic stops, and opacities', () {
      final Uint8List bytes = legacyLibrary([
        (
          name: 'Old',
          colors: [
            (location: 0, midpoint: 50, model: 0, components: [65535, 32896, 0, 0], type: 0),
            (location: 1024, midpoint: 40, model: 2, components: [65535, 0, 65535, 65535], type: 0),
            (location: 2048, midpoint: 50, model: 8, components: [2500, 0, 0, 0], type: 0),
            (location: 4096, midpoint: 50, model: 0, components: [0, 0, 0, 0], type: 1),
          ],
          opacities: [(location: 0, midpoint: 50, opacity: 255), (location: 4096, midpoint: 50, opacity: 51)],
        ),
      ]);

      final GrdFile file = GrdDecoder.decode(bytes);
      final PsGradient gradient = file.gradients.single.gradient;

      check(file.version).equals(3);
      check(file.warnings).isEmpty();
      check(gradient.name).equals('Old');
      check(gradient.colorStops.map((stop) => stop.kind?.value).toList()).deepEquals(['UsrS', 'UsrS', 'UsrS', 'FrgC']);
      check(gradient.colorStops[0].color?.green).equals(128);
      check(gradient.colorStops[1].color?.component('Mgnt')?.value).equals(100);
      check(gradient.colorStops[1].midpoint).equals(40);
      check(gradient.colorStops[2].color?.component('Gry ')?.value).equals(75);
      check(gradient.colorStops[3].color).isNull();
      check(gradient.transparencyStops.last.opacity?.value).equals(20);

      final GrdFile upgraded = GrdDecoder.decode(GrdEncoder.encode(file));
      check(upgraded.version).equals(5);
      check(upgraded.gradients.single.gradient.colorStops).length.equals(4);
    });

    test('reports unsupported color models', () {
      final Uint8List bytes = legacyLibrary([
        (
          name: 'Spot',
          colors: [
            (location: 0, midpoint: 50, model: 3, components: [1, 2, 3, 4], type: 0),
          ],
          opacities: const [],
        ),
      ]);

      check(GrdDecoder.decode(bytes).warnings.single.message).contains('model 3');
      check(() => GrdDecoder.decode(bytes, options: const GrdDecodeOptions(mode: GrdDecodeMode.strict))).throws<GrdFormatException>();
    });
  });

  group('malformed input', () {
    test('rejects foreign signatures, versions, and oversized files', () {
      check(() => GrdDecoder.decode(Uint8List.fromList(ascii.encode('8BPT\u0000\u0005')))).throws<GrdFormatException>();
      check(() => GrdDecoder.decode(Uint8List.fromList([...ascii.encode('8BGR'), 0, 4]))).throws<GrdFormatException>();
      check(() => GrdDecoder.decode(Uint8List(64), options: const GrdDecodeOptions(maxFileBytes: 32))).throws<GrdFormatException>();
      check(() => GrdDecoder.decode(Uint8List.fromList(ascii.encode('8BGR')))).throws<GrdFormatException>();
    });

    test('keeps trailing bytes as a warning unless strict', () {
      final Uint8List bytes = Uint8List.fromList([...GrdEncoder.encode(GrdFile.create(const [])), 1, 2, 3]);

      final GrdFile file = GrdDecoder.decode(bytes);

      check(file.trailingData).deepEquals([1, 2, 3]);
      check(file.warnings).length.equals(1);
      check(GrdEncoder.encode(file)).deepEquals(bytes);
      check(() => GrdDecoder.decode(bytes, options: const GrdDecodeOptions(mode: GrdDecodeMode.strict))).throws<GrdFormatException>();
    });
  });
}

/// Reads one base64-encoded fixture.
Uint8List _fixture(String name) => base64Decode(File('test/fixtures/$name.b64').readAsStringSync().replaceAll(RegExp(r'\s'), ''));
