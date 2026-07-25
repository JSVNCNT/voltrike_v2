import 'package:flutter/foundation.dart';

@immutable
class RideBottomSheetState {
  const RideBottomSheetState({this.isExpanded = false});

  final bool isExpanded;

  RideBottomSheetState copyWith({bool? isExpanded}) {
    return RideBottomSheetState(
      isExpanded: isExpanded ?? this.isExpanded,
    );
  }
}
