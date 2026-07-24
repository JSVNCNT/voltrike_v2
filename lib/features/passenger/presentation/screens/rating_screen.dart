import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../common/presentation/widgets/star_rating.dart';
import '../../providers/driver_rating_provider.dart';

/// ===========================================================================
/// Rating Screen
///
/// Displayed after a completed trip.
///
/// Allows the passenger to:
/// • Rate the driver
/// • Leave an optional comment
/// • Submit feedback
/// ===========================================================================
class RatingScreen extends ConsumerStatefulWidget {
  const RatingScreen({
    super.key,
    required this.bookingId,
  });

  final String bookingId;

  @override
  ConsumerState<RatingScreen> createState() =>
      _RatingScreenState();
}

class _RatingScreenState
    extends ConsumerState<RatingScreen> {
  //==========================================================================
  // Controllers
  //==========================================================================

  final TextEditingController _commentController =
      TextEditingController();

  //==========================================================================
  // State
  //==========================================================================

double _rating = 5.0;



  bool _submitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  //==========================================================================
  // Submit
  //==========================================================================

  Future<void> _submitRating() async {
    if (_submitting) {
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      await ref
          .read(
            driverRatingControllerProvider.notifier,
          )
          .submitRating(
            bookingId: widget.bookingId,
            rating: _rating.round(),
            comment: _commentController.text.trim(),
          );

      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (_) {
          return AlertDialog(
            title: const Text(
              'Thank You!',
            ),
            content: const Text(
              'Your rating has been submitted successfully.',
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text(
                  'OK',
                ),
              ),
            ],
          );
        },
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).popUntil(
        (route) => route.isFirst,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString(),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  //==========================================================================
  // Build
  //==========================================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Rate Your Driver',
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(
            24,
          ),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              const SizedBox(
                height: 20,
              ),

              const Icon(
                Icons.emoji_emotions,
                size: 96,
                color: Colors.amber,
              ),

              const SizedBox(
                height: 24,
              ),

              const Text(
                'How was your trip?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(
                height: 12,
              ),

              const Text(
                'Your feedback helps improve the experience for everyone.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 16,
                ),
              ),

              const SizedBox(
                height: 40,
              ),

              //----------------------------------------------------------------
              // Star Rating
              //----------------------------------------------------------------

              StarRating(
                rating: _rating,
                onRatingChanged: (rating) {
                  setState(() {
                    _rating = rating;
                  });
                },
              ),

              const SizedBox(
                height: 40,
              ),

                            //----------------------------------------------------------------
              // Comment
              //----------------------------------------------------------------

              TextField(
                controller: _commentController,
                maxLines: 5,
                textCapitalization:
                    TextCapitalization.sentences,
                decoration:
                    const InputDecoration(
                  labelText:
                      'Comment (Optional)',
                  hintText:
                      'Tell us about your experience...',
                  border:
                      OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),

              const SizedBox(
                height: 32,
              ),

              //----------------------------------------------------------------
              // Trip Summary
              //----------------------------------------------------------------

              Card(
                child: Padding(
                  padding:
                      const EdgeInsets.all(
                    16,
                  ),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                    children: [
                      const Text(
                        'Trip Summary',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),

                      const SizedBox(
                        height: 12,
                      ),

                      Text(
                        'Booking ID: ${widget.bookingId}',
                      ),

                      const SizedBox(
                        height: 8,
                      ),

                      Text(
                        'Rating: ${_rating.toInt()} ★',
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(
                height: 40,
              ),

              //----------------------------------------------------------------
              // Submit
              //----------------------------------------------------------------

              FilledButton.icon(
                onPressed: _submitting
                    ? null
                    : _submitRating,
                icon: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child:
                            CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(
                        Icons.send,
                      ),
                label: Text(
                  _submitting
                      ? 'Submitting...'
                      : 'Submit Rating',
                ),
              ),

              const SizedBox(
                height: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}