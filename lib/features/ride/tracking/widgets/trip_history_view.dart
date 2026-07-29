import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../data/models/booking.dart';
import '../../../../data/models/booking_state_machine.dart';
import '../../../common/presentation/widgets/empty_state.dart';

enum TripHistoryFilter { all, completed, cancelled }

typedef TripHistoryItemBuilder =
    Widget Function(BuildContext context, Booking booking);

/// Shared passenger/driver history layout with local terminal-state filtering.
class TripHistoryView extends StatefulWidget {
  const TripHistoryView({
    super.key,
    required this.bookings,
    required this.itemBuilder,
  });

  final List<Booking> bookings;
  final TripHistoryItemBuilder itemBuilder;

  @override
  State<TripHistoryView> createState() => _TripHistoryViewState();
}

class _TripHistoryViewState extends State<TripHistoryView> {
  static const _pageSize = 10;

  TripHistoryFilter _filter = TripHistoryFilter.all;
  int _visibleCount = _pageSize;

  List<Booking> get _filtered {
    return widget.bookings.where((booking) {
      return switch (_filter) {
        TripHistoryFilter.all => true,
        TripHistoryFilter.completed =>
          booking.status == BookingStatus.completed,
        TripHistoryFilter.cancelled =>
          booking.status == BookingStatus.cancelled,
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final visible = filtered.take(_visibleCount).toList();
    final entries = _entriesFor(
      visible,
      hasMore: filtered.length > visible.length,
    );

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          sliver: SliverToBoxAdapter(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<TripHistoryFilter>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: TripHistoryFilter.all,
                    label: Text('All'),
                  ),
                  ButtonSegment(
                    value: TripHistoryFilter.completed,
                    label: Text('Completed'),
                  ),
                  ButtonSegment(
                    value: TripHistoryFilter.cancelled,
                    label: Text('Cancelled'),
                  ),
                ],
                selected: {_filter},
                onSelectionChanged: (selection) {
                  setState(() {
                    _filter = selection.single;
                    _visibleCount = _pageSize;
                  });
                },
              ),
            ),
          ),
        ),
        if (filtered.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              title: _filter == TripHistoryFilter.all
                  ? 'No trips yet'
                  : 'No ${_filter.name} trips',
              message: _filter == TripHistoryFilter.all
                  ? 'Completed and cancelled trips will appear here.'
                  : 'Try another history filter.',
              icon: Icons.route_outlined,
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverList.builder(
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                return switch (entry) {
                  _DateHeader(:final label) => Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  _TripEntry(:final booking) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: widget.itemBuilder(context, booking),
                  ),
                  _LoadMore() => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() => _visibleCount += _pageSize);
                      },
                      icon: const Icon(Icons.expand_more_rounded),
                      label: const Text('Load more trips'),
                    ),
                  ),
                };
              },
            ),
          ),
      ],
    );
  }

  List<_HistoryEntry> _entriesFor(
    List<Booking> visible, {
    required bool hasMore,
  }) {
    final entries = <_HistoryEntry>[];
    String? previous;
    for (final booking in visible) {
      final label = _dateGroupLabel(BookingStateMachine.terminalDate(booking));
      if (label != previous) {
        entries.add(_DateHeader(label));
        previous = label;
      }
      entries.add(_TripEntry(booking));
    }
    if (hasMore) entries.add(const _LoadMore());
    return entries;
  }
}

String _dateGroupLabel(DateTime value) {
  final date = DateTime(value.year, value.month, value.day);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final difference = today.difference(date).inDays;

  if (difference == 0) return 'Today';
  if (difference == 1) return 'Yesterday';
  if (date.year == today.year) return DateFormat('MMMM d').format(date);
  return DateFormat('MMMM d, yyyy').format(date);
}

sealed class _HistoryEntry {
  const _HistoryEntry();
}

class _DateHeader extends _HistoryEntry {
  const _DateHeader(this.label);
  final String label;
}

class _TripEntry extends _HistoryEntry {
  const _TripEntry(this.booking);
  final Booking booking;
}

class _LoadMore extends _HistoryEntry {
  const _LoadMore();
}
