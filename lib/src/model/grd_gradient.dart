import 'package:pscore/pscore.dart';

/// One entry of a GRD gradient list.
///
/// Photoshop wraps every gradient in a `Grdn` object whose `Grad` key holds
/// the gradient itself. The wrapper is kept so that unknown keys survive a
/// decode and encode round trip.
final class GrdGradient {
  /// Complete list-entry descriptor, including the wrapped gradient.
  final PsDescriptor descriptor;

  /// Typed view over the wrapped gradient.
  final PsGradient gradient;

  /// Creates an entry from a list [descriptor] and its decoded [gradient].
  const GrdGradient({
    required this.descriptor,
    required this.gradient,
  });

  /// Wraps [gradient] the way Photoshop writes new library entries.
  factory GrdGradient.create(PsGradient gradient) => GrdGradient(
    descriptor: PsDescriptor(
      name: 'Gradient\u0000',
      classId: 'Grdn',
      items: [
        PsDescriptorItem(
          key: 'Grad',
          value: PsObjectValue(value: gradient.descriptor),
        ),
      ],
    ),
    gradient: gradient,
  );

  /// Reads one list-entry [descriptor], or returns `null` when it holds no gradient.
  ///
  /// Entries whose wrapper is itself the gradient are accepted as well.
  static GrdGradient? tryFromDescriptor(PsDescriptor descriptor) {
    final PsDescriptor? wrapped = descriptor.objectValue('Grad') ?? (descriptor.value('GrdF') == null ? null : descriptor);
    return wrapped == null ? null : GrdGradient(descriptor: descriptor, gradient: PsGradient.fromDescriptor(wrapped));
  }

  /// Gradient name stored by Photoshop, when present.
  String? get name => gradient.name;

  /// Returns a copy whose wrapped gradient is replaced by [gradient].
  GrdGradient withGradient(PsGradient gradient) => identical(descriptor, this.gradient.descriptor)
      ? GrdGradient(descriptor: gradient.descriptor, gradient: gradient)
      : GrdGradient(
          descriptor: descriptor.withValue('Grad', PsObjectValue(value: gradient.descriptor)),
          gradient: gradient,
        );
}
