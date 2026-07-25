import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

class DriverOfferCooldown {
  const DriverOfferCooldown({this.until});

  final DateTime? until;

  bool get isActive => until?.isAfter(DateTime.now()) ?? false;

  int get secondsRemaining {
    if (!isActive) return 0;
    return until!.difference(DateTime.now()).inSeconds + 1;
  }
}

class DriverOfferCooldownNotifier extends StateNotifier<DriverOfferCooldown> {
  DriverOfferCooldownNotifier() : super(const DriverOfferCooldown());

  Timer? _timer;

  void start([Duration duration = const Duration(seconds: 30)]) {
    _timer?.cancel();
    final until = DateTime.now().add(duration);
    state = DriverOfferCooldown(until: until);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!until.isAfter(DateTime.now())) {
        clear();
        return;
      }
      state = DriverOfferCooldown(until: until);
    });
  }

  void clear() {
    _timer?.cancel();
    _timer = null;
    state = const DriverOfferCooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final driverOfferCooldownProvider = StateNotifierProvider<
    DriverOfferCooldownNotifier, DriverOfferCooldown>(
  (ref) => DriverOfferCooldownNotifier(),
);
