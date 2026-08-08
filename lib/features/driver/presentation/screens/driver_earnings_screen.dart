import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_semantic_colors.dart';
import '../../../../core/widgets/cards/app_card.dart';
import '../../../common/presentation/widgets/app_app_bar.dart';
import '../../controllers/driver_earnings_controller.dart';

class DriverEarningsScreen extends ConsumerWidget {
  const DriverEarningsScreen({super.key, required this.driverId});

  final String driverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final earnings = ref.watch(driverEarningsProvider(driverId));

    return Scaffold(
      appBar: const AppAppBar(title: 'Driver Earnings', centerTitle: true),
      body: earnings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(error.toString(), textAlign: TextAlign.center),
          ),
        ),
        data: (data) => DriverEarningsSummaryView(data: data),
      ),
    );
  }
}

class DriverEarningsSummaryView extends StatelessWidget {
  const DriverEarningsSummaryView({super.key, required this.data});

  final DriverEarningsSummary data;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final semantic = AppSemanticColors.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _EarningsCard(
          title: "Today's earnings",
          value: _currency(data.today),
          icon: Icons.today_outlined,
          accentColor: semantic.success,
        ),
        const SizedBox(height: 12),
        _EarningsCard(
          title: 'Completed-trip amount',
          value: _currency(data.completedTripAmount),
          icon: Icons.receipt_long_outlined,
          accentColor: colors.primary,
        ),
        const SizedBox(height: 12),
        _EarningsCard(
          title: 'Weekly earnings',
          value: _currency(data.week),
          icon: Icons.date_range_outlined,
          accentColor: colors.primary,
        ),
        const SizedBox(height: 12),
        _EarningsCard(
          title: 'Monthly earnings',
          value: _currency(data.month),
          icon: Icons.calendar_month_outlined,
          accentColor: semantic.info,
        ),
        const SizedBox(height: 12),
        _EarningsCard(
          title: 'Total net earnings',
          value: _currency(data.total),
          icon: Icons.payments_outlined,
          accentColor: semantic.success,
        ),
        const SizedBox(height: 12),
        _EarningsCard(
          title: 'Completed trips',
          value: data.completedTrips.toString(),
          icon: Icons.route_outlined,
          accentColor: colors.primary,
        ),
        const SizedBox(height: 12),
        _EarningsCard(
          title: 'Average net earnings',
          value: _currency(data.averageFare),
          icon: Icons.account_balance_wallet_outlined,
          accentColor: semantic.warning,
        ),
      ],
    );
  }
}

class _EarningsCard extends StatelessWidget {
  const _EarningsCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.accentColor,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      accentColor: accentColor,
      tintColor: accentColor,
      child: ListTile(
        minTileHeight: 82,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: accentColor),
        ),
        title: Text(title),
        subtitle: Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

String _currency(double value) => '₱${value.toStringAsFixed(2)}';
