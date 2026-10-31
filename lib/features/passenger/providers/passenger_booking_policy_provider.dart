import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/passenger_booking_policy.dart';

final _policyUserProvider = StreamProvider.autoDispose<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

final passengerBookingPolicyProvider =
    StreamProvider.autoDispose<PassengerBookingPolicy>((ref) {
      final uid =
          ref.watch(_policyUserProvider).value?.uid ??
          FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        return Stream.value(const PassengerBookingPolicy());
      }
      final controller = StreamController<PassengerBookingPolicy>();
      Map<String, dynamic>? latest;
      String? lastSignature;
      void emit() {
        if (latest != null && !controller.isClosed) {
          final policy = PassengerBookingPolicy.fromMap(latest!);
          final signature =
              '${policy.notice}|${policy.isBlocked}|'
              '${policy.strikes.join(',')}|${policy.appealableBookings.join(',')}|'
              '${policy.canAppealRestriction}|${policy.appealPending}';
          if (signature != lastSignature) {
            lastSignature = signature;
            controller.add(policy);
          }
        }
      }

      final subscription = FirebaseFirestore.instance
          .collection('passengerBookingPolicies')
          .doc(uid)
          .snapshots()
          .listen((snapshot) {
            latest = snapshot.data() ?? {};
            emit();
          }, onError: controller.addError);
      // Expire cooldowns and rolling strikes even while the screen stays open.
      final timer = Timer.periodic(const Duration(seconds: 1), (_) => emit());
      ref.onDispose(() {
        timer.cancel();
        unawaited(subscription.cancel());
        unawaited(controller.close());
      });
      return controller.stream;
    });
