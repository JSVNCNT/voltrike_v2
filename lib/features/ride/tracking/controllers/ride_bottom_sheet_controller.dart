import 'package:flutter_riverpod/legacy.dart';

import '../models/ride_bottom_sheet_state.dart';

class RideBottomSheetController
    extends StateNotifier<RideBottomSheetState> {
  RideBottomSheetController() : super(const RideBottomSheetState());

  void setExpanded(bool expanded) {
    state = state.copyWith(isExpanded: expanded);
  }

  void toggle() {
    setExpanded(!state.isExpanded);
  }
}

final rideBottomSheetProvider = StateNotifierProvider.autoDispose<
    RideBottomSheetController, RideBottomSheetState>((ref) {
  return RideBottomSheetController();
});
