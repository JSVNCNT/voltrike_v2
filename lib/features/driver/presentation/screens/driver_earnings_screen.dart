import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/driver_earnings_controller.dart';

class DriverEarningsScreen extends ConsumerWidget {
  const DriverEarningsScreen({
    super.key,
    required this.driverId,
  });

  final String driverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final earnings =
        ref.watch(driverEarningsProvider(driverId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Earnings'),
        centerTitle: true,
      ),
      body: earnings.when(
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              error.toString(),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (data) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildCard(
                title: "Today's Earnings",
                value: "₱${data.today.toStringAsFixed(2)}",
                icon: Icons.today,
              ),
              const SizedBox(height: 12),
              _buildCard(
                title: "Weekly Earnings",
                value: "₱${data.week.toStringAsFixed(2)}",
                icon: Icons.date_range,
              ),
              const SizedBox(height: 12),
              _buildCard(
                title: "Monthly Earnings",
                value: "₱${data.month.toStringAsFixed(2)}",
                icon: Icons.calendar_month,
              ),
              const SizedBox(height: 12),
              _buildCard(
                title: "Total Earnings",
                value: "₱${data.total.toStringAsFixed(2)}",
                icon: Icons.payments,
              ),
              const SizedBox(height: 12),
              _buildCard(
                title: "Completed Trips",
                value: data.completedTrips.toString(),
                icon: Icons.route,
              ),
              const SizedBox(height: 12),
              _buildCard(
                title: "Average Fare",
                value: "₱${data.averageFare.toStringAsFixed(2)}",
                icon: Icons.attach_money,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Card(
      elevation: 3,
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(icon),
        ),
        title: Text(title),
        subtitle: Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}