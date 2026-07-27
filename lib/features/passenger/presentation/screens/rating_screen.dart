import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/errors/domain_error_mapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../common/presentation/widgets/app_app_bar.dart';
import '../../../common/presentation/widgets/star_rating.dart';
import '../../providers/booking_listener_provider.dart';
import '../../providers/driver_rating_provider.dart';

class RatingScreen extends ConsumerStatefulWidget {
  const RatingScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  ConsumerState<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends ConsumerState<RatingScreen> {
  final _commentController = TextEditingController();

  double _rating = 5;
  bool _checkingExisting = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _skipIfAlreadyRated();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _skipIfAlreadyRated() async {
    try {
      final user = AuthRepository().currentUser;
      if (user == null) return;
      final alreadyRated = await ref
          .read(driverRatingRepositoryProvider)
          .hasRatingForBooking(
            bookingId: widget.bookingId,
            passengerId: user.uid,
          );
      if (alreadyRated && mounted) {
        context.go(AppRoutes.passengerReceipt, extra: widget.bookingId);
      }
    } catch (_) {
      // Submission remains safe because the backend operation is idempotent.
    } finally {
      if (mounted) setState(() => _checkingExisting = false);
    }
  }

  Future<void> _submitRating() async {
    if (_submitting) return;
    setState(() => _submitting = true);

    try {
      await ref
          .read(driverRatingControllerProvider.notifier)
          .submitRating(
            bookingId: widget.bookingId,
            rating: _rating.round(),
            comment: _commentController.text.trim(),
          );
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(
            Icons.check_circle_outline_rounded,
            color: AppColors.success,
          ),
          title: const Text('Rating submitted'),
          content: const Text(
            'Thank you for helping keep VolTrike rides reliable.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('View receipt'),
            ),
          ],
        ),
      );
      if (mounted) {
        context.go(AppRoutes.passengerReceipt, extra: widget.bookingId);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DomainErrorMapper.message(error))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final booking = ref
        .watch(bookingListenerProvider(widget.bookingId))
        .asData
        ?.value;

    return Scaffold(
      appBar: const AppAppBar(title: 'Rate your driver'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.rating.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.star_rounded,
                  size: 34,
                  color: AppColors.rating,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'How was your trip?',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Your feedback helps improve the experience for everyone.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            if (booking != null) ...[
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: AppColors.primaryContainer,
                        foregroundImage:
                            booking.driverPhotoUrl?.isNotEmpty == true
                            ? NetworkImage(booking.driverPhotoUrl!)
                            : null,
                        child: booking.driverPhotoUrl?.isNotEmpty == true
                            ? null
                            : const Icon(Icons.person_outline_rounded),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              booking.driverName ?? 'Your driver',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              booking.destinationAddress,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 28),
            Center(
              child: StarRating(
                rating: _rating,
                size: 36,
                onRatingChanged: (rating) {
                  setState(() => _rating = rating);
                },
              ),
            ),
            const SizedBox(height: 10),
            Semantics(
              liveRegion: true,
              child: Text(
                '${_rating.round()} out of 5',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: _commentController,
              maxLines: 5,
              maxLength: 1000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Comment (optional)',
                hintText: 'Tell us about your experience',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _submitting || _checkingExisting
                  ? null
                  : _submitRating,
              icon: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(
                _submitting
                    ? 'Submitting…'
                    : _checkingExisting
                    ? 'Checking trip…'
                    : 'Submit rating',
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _submitting
                  ? null
                  : () => context.go(
                      AppRoutes.passengerReceipt,
                      extra: widget.bookingId,
                    ),
              child: const Text('Skip for now'),
            ),
          ],
        ),
      ),
    );
  }
}
