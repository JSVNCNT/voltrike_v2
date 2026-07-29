import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/routes.dart';
import '../../../core/errors/domain_error_mapper.dart';
import '../../../core/theme/app_semantic_colors.dart';
import '../../../data/models/driver_violation_case.dart';
import '../../../data/repositories/driver_violation_repository.dart';
import '../../common/presentation/widgets/app_app_bar.dart';

class DriverViolationListScreen extends StatefulWidget {
  const DriverViolationListScreen({super.key, this.repository});

  final DriverViolationRepository? repository;

  @override
  State<DriverViolationListScreen> createState() =>
      _DriverViolationListScreenState();
}

class _DriverViolationListScreenState extends State<DriverViolationListScreen> {
  late final DriverViolationRepository _repository =
      widget.repository ?? DriverViolationRepository();
  late Future<List<DriverViolationCase>> _future = _load();

  Future<List<DriverViolationCase>> _load() => _repository.listMyViolations();

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppAppBar(title: 'Restricted-area cases'),
      body: FutureBuilder<List<DriverViolationCase>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _LoadFailure(
              message: DomainErrorMapper.message(snapshot.error!),
              onRetry: _refresh,
            );
          }
          final cases = snapshot.data ?? const [];
          if (cases.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Icon(Icons.verified_user_outlined, size: 52),
                  SizedBox(height: 16),
                  Center(child: Text('No restricted-area cases')),
                  SizedBox(height: 8),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 36),
                    child: Text(
                      'Confirmed cases and messages from TODA or developer '
                      'administrators will appear here.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              itemCount: cases.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) =>
                  _ViolationCard(violation: cases[index]),
            ),
          );
        },
      ),
    );
  }
}

class _ViolationCard extends StatelessWidget {
  const _ViolationCard({required this.violation});

  final DriverViolationCase violation;

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () =>
            context.push('${AppRoutes.driverViolations}/${violation.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    violation.isOpen
                        ? Icons.report_problem_rounded
                        : Icons.task_alt_rounded,
                    color: violation.isOpen ? colors.error : semantic.success,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      violation.restrictionName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${_status(violation.status)} • '
                '${_contextLabel(violation.context)}',
              ),
              const SizedBox(height: 4),
              Text(
                DateFormat('MMM d, y • h:mm a').format(violation.createdAt),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadFailure extends StatelessWidget {
  const _LoadFailure({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 44),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

String _status(String value) {
  return switch (value) {
    'acknowledged' => 'Acknowledged',
    'responding' => 'Admin responding',
    'resolved' => 'Resolved',
    'dismissed' => 'Dismissed',
    _ => 'Open',
  };
}

String _contextLabel(String context) {
  return switch (context) {
    'to_pickup' => 'Driving to pickup',
    'active_trip' || 'active_booking' => 'During booking',
    _ => 'Online idle',
  };
}
