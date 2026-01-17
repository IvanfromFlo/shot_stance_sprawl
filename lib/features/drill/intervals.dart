import 'dart:math' as math;

abstract class IntervalStrategy {
  /// Returns seconds (double) between min and max.
  double next(double minSeconds, double maxSeconds);
}

class UniformIntervalStrategy implements IntervalStrategy {
  final _rng = math.Random();
  @override
  double next(double minSeconds, double maxSeconds) {
    if (maxSeconds < minSeconds) {
      final t = minSeconds; minSeconds = maxSeconds; maxSeconds = t;
    }
    final delta = maxSeconds - minSeconds;
    return minSeconds + _rng.nextDouble() * delta;
  }
}

