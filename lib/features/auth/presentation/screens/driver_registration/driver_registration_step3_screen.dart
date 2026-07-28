import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/routes.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/utils/validators.dart';
import '../../../../../core/widgets/buttons/primary_button.dart';
import '../../../../../core/widgets/inputs/app_text_field.dart';

import '../../providers/driver_registration_data_provider.dart';

import '../../widgets/auth_header.dart';
import '../../widgets/auth_logo.dart';
import '../../widgets/auth_scaffold.dart';
import '../../widgets/loading_overlay.dart';
import '../../widgets/registration_back_scope.dart';
import '../../widgets/registration_step_indicator.dart';
import '../../widgets/validation_message.dart';

class DriverRegistrationStep3Screen extends ConsumerStatefulWidget {
  const DriverRegistrationStep3Screen({super.key, this.returnToReview = false});

  final bool returnToReview;

  @override
  ConsumerState<DriverRegistrationStep3Screen> createState() =>
      _DriverRegistrationStep3ScreenState();
}

class _DriverRegistrationStep3ScreenState
    extends ConsumerState<DriverRegistrationStep3Screen> {
  final _formKey = GlobalKey<FormState>();

  final _plateController = TextEditingController();

  final _brandController = TextEditingController();

  final _modelController = TextEditingController();

  final _colorController = TextEditingController();

  String? _vehicleType;
  int _seatingCapacity = 3;

  String? _error;

  final List<String> _vehicleTypes = ['Electric Tuktuk', 'E-Trike'];

  @override
  void initState() {
    super.initState();

    final registration = ref.read(driverRegistrationDataProvider);

    _vehicleType = _vehicleTypes.contains(registration.vehicleType)
        ? registration.vehicleType
        : null;

    _plateController.text = registration.plateNumber;

    _brandController.text = registration.vehicleBrand;

    _modelController.text = registration.vehicleModel;

    _colorController.text = registration.vehicleColor;

    _seatingCapacity = registration.vehicleType == 'E-Trike'
        ? 2
        : registration.seatingCapacity.clamp(3, 4);
  }

  @override
  void dispose() {
    _plateController.dispose();
    _brandController.dispose();
    _modelController.dispose();
    _colorController.dispose();
    super.dispose();
  }

  void _continue() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_vehicleType == null) {
      setState(() {
        _error = 'Please select a vehicle type.';
      });

      return;
    }

    setState(() {
      _error = null;
    });

    ref
        .read(driverRegistrationDataProvider.notifier)
        .updateData(
          vehicleType: _vehicleType,
          plateNumber: _plateController.text.trim(),
          vehicleBrand: _brandController.text.trim(),
          vehicleModel: _modelController.text.trim(),
          vehicleColor: _colorController.text.trim(),
          seatingCapacity: _vehicleType == 'E-Trike' ? 2 : _seatingCapacity,
        );

    context.go(
      widget.returnToReview
          ? AppRoutes.driverRegisterReview
          : AppRoutes.uploadDocuments,
    );
  }

  @override
  Widget build(BuildContext context) {
    return RegistrationBackScope(
      fallbackRoute: widget.returnToReview
          ? AppRoutes.driverRegisterReview
          : AppRoutes.driverRegisterStep2,
      child: LoadingOverlay(
        isLoading: false,
        child: AuthScaffold(
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  const AuthLogo(logoSize: 72),

                  const SizedBox(height: AppSpacing.xl),

                  const AuthHeader(
                    title: 'Driver registration',
                    subtitle: 'Vehicle information',
                  ),

                  const SizedBox(height: AppSpacing.lg),
                  const RegistrationStepIndicator(
                    currentStep: 3,
                    totalSteps: 5,
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  if (_error != null) ...[
                    ValidationMessage(message: _error!),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  DropdownButtonFormField<String>(
                    initialValue:
                        (_vehicleType != null &&
                            _vehicleTypes.contains(_vehicleType))
                        ? _vehicleType
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Vehicle Type',
                    ),
                    items: _vehicleTypes
                        .map(
                          (type) => DropdownMenuItem<String>(
                            value: type,
                            child: Text(type),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _vehicleType = value;
                        _seatingCapacity = value == 'E-Trike' ? 2 : 3;
                      });
                    },
                    validator: (value) {
                      if (value == null) {
                        return 'Please select a vehicle type.';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: AppSpacing.md),

                  AppTextField(
                    controller: _plateController,
                    label: 'Plate Number',
                    hint: 'ABC-1234',
                    prefixIcon: Icons.pin_outlined,
                    textInputAction: TextInputAction.next,
                    validator: (value) => Validators.validateRequired(
                      value,
                      fieldName: 'Plate Number',
                    ),
                  ),

                  const SizedBox(height: AppSpacing.md),

                  AppTextField(
                    controller: _brandController,
                    label: 'Vehicle Brand',
                    hint: 'Bajaj',
                    prefixIcon: Icons.directions_car,
                    textInputAction: TextInputAction.next,
                    validator: (value) => Validators.validateRequired(
                      value,
                      fieldName: 'Vehicle Brand',
                    ),
                  ),

                  const SizedBox(height: AppSpacing.md),

                  AppTextField(
                    controller: _modelController,
                    label: 'Vehicle Model',
                    hint: '2024 Model',
                    prefixIcon: Icons.directions_car,
                    textInputAction: TextInputAction.next,
                    validator: (value) => Validators.validateRequired(
                      value,
                      fieldName: 'Vehicle Model',
                    ),
                  ),

                  const SizedBox(height: AppSpacing.md),

                  AppTextField(
                    controller: _colorController,
                    label: 'Vehicle Color',
                    hint: 'Blue',
                    prefixIcon: Icons.palette_outlined,
                    textInputAction: TextInputAction.next,
                    validator: (value) => Validators.validateRequired(
                      value,
                      fieldName: 'Vehicle Color',
                    ),
                  ),

                  const SizedBox(height: AppSpacing.md),

                  if (_vehicleType != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _vehicleType == 'E-Trike'
                                  ? 'Passenger capacity: 2'
                                  : 'Passenger seating capacity',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _vehicleType == 'E-Trike'
                                  ? 'E-Trikes are registered with a fixed maximum '
                                        'of 2 passenger seats.'
                                  : 'Electric tuktuks may register 3 or 4 '
                                        'passenger seats. This limit controls '
                                        'which bookings the driver may receive.',
                            ),
                            if (_vehicleType == 'Electric Tuktuk') ...[
                              const SizedBox(height: AppSpacing.md),
                              Row(
                                children: [
                                  IconButton.outlined(
                                    onPressed: _seatingCapacity > 3
                                        ? () =>
                                              setState(() => _seatingCapacity--)
                                        : null,
                                    icon: const Icon(Icons.remove),
                                    tooltip: 'Reduce capacity',
                                  ),
                                  Expanded(
                                    child: Slider(
                                      value: _seatingCapacity.toDouble(),
                                      min: 3,
                                      max: 4,
                                      divisions: 1,
                                      label: '$_seatingCapacity seats',
                                      onChanged: (value) => setState(
                                        () => _seatingCapacity = value.round(),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '$_seatingCapacity',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                  IconButton.outlined(
                                    onPressed: _seatingCapacity < 4
                                        ? () =>
                                              setState(() => _seatingCapacity++)
                                        : null,
                                    icon: const Icon(Icons.add),
                                    tooltip: 'Increase capacity',
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: AppSpacing.xl),
                  PrimaryButton(
                    text: widget.returnToReview ? 'Save changes' : 'Continue',
                    onPressed: _continue,
                  ),

                  const SizedBox(height: AppSpacing.lg),

                  TextButton.icon(
                    onPressed: () {
                      context.go(
                        widget.returnToReview
                            ? AppRoutes.driverRegisterReview
                            : AppRoutes.driverRegisterStep2,
                      );
                    },
                    icon: const Icon(Icons.arrow_back),
                    label: Text(
                      widget.returnToReview
                          ? 'Cancel and return to review'
                          : 'Back',
                    ),
                  ),

                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
