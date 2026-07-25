import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/ride_tracking_controller.dart';
import '../models/ride_tracking_state.dart';

final rideTrackingProvider = StateNotifierProvider.autoDispose<
    RideTrackingController, RideTrackingState>((ref) {
  return RideTrackingController();
});
