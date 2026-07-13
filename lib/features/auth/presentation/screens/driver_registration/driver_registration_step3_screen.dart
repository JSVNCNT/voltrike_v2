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
import '../../widgets/validation_message.dart';

class DriverRegistrationStep3Screen
    extends ConsumerStatefulWidget {
  const DriverRegistrationStep3Screen({
    super.key,
  });

  @override
  ConsumerState<DriverRegistrationStep3Screen>
      createState() =>
          _DriverRegistrationStep3ScreenState();
}

class _DriverRegistrationStep3ScreenState
    extends ConsumerState<
        DriverRegistrationStep3Screen> {
  final _formKey = GlobalKey<FormState>();

  final _plateController =
      TextEditingController();

  final _brandController =
      TextEditingController();

  final _modelController =
      TextEditingController();

  final _colorController =
      TextEditingController();

  final _capacityController =
      TextEditingController();

  String? _vehicleType;

  String? _error;

  final List<String> _vehicleTypes = [
    'Electric Tuktuk',
    'E-Trike',
  ];

  @override
  void initState() {
    super.initState();

    final registration =
        ref.read(driverRegistrationDataProvider);

    _vehicleType =
        registration.vehicleType;

    _plateController.text =
        registration.plateNumber;

    _brandController.text =
        registration.vehicleBrand;

    _modelController.text =
        registration.vehicleModel;

    _colorController.text =
        registration.vehicleColor;

    _capacityController.text =
        registration.seatingCapacity == 0
            ? ''
            : registration.seatingCapacity
                .toString();
  }

  @override
  void dispose() {
    _plateController.dispose();
    _brandController.dispose();
    _modelController.dispose();
    _colorController.dispose();
    _capacityController.dispose();

    super.dispose();
  }

  void _continue() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_vehicleType == null) {
      setState(() {
        _error =
            'Please select a vehicle type.';
      });

      return;
    }

    setState(() {
      _error = null;
    });

    ref
        .read(
          driverRegistrationDataProvider
              .notifier,
        )
        .updateData(
          vehicleType: _vehicleType,
          plateNumber:
              _plateController.text.trim(),
          vehicleBrand:
              _brandController.text.trim(),
          vehicleModel:
              _modelController.text.trim(),
          vehicleColor:
              _colorController.text.trim(),
          seatingCapacity: int.tryParse(
                _capacityController.text,
              ) ??
              0,
        );

    context.go(
      AppRoutes.uploadDocuments,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LoadingOverlay(
      isLoading: false,
      child: AuthScaffold(
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                const SizedBox(
                  height: AppSpacing.lg,
                ),

                const AuthLogo(
                  logoSize: 90,
                ),

                const SizedBox(
                  height: AppSpacing.xl,
                ),

                const AuthHeader(
                  title:
                      'Driver Registration',
                  subtitle:
                      'Step 3 of 4\nVehicle Information',
                ),

                const SizedBox(
                  height: AppSpacing.lg,
                ),

                if (_error != null) ...[
                  ValidationMessage(
                    message: _error!,
                  ),
                  const SizedBox(
                    height: AppSpacing.md,
                  ),
                ],
                 DropdownButtonFormField<String>(
  initialValue: (_vehicleType != null &&
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
    });
  },
  validator: (value) {
    if (value == null) {
      return 'Please select a vehicle type.';
    }
    return null;
  },
),

                const SizedBox(
                  height: AppSpacing.md,
                ),

                AppTextField(
                  controller:
                      _plateController,
                  label: 'Plate Number',
                  hint: 'ABC-1234',
                  prefixIcon:
                      Icons.pin_outlined,
                  textInputAction:
                      TextInputAction.next,
                  validator: (value) =>
                      Validators.validateRequired(
                    value,
                    fieldName:
                        'Plate Number',
                  ),
                ),

                const SizedBox(
                  height: AppSpacing.md,
                ),

                AppTextField(
                  controller:
                      _brandController,
                  label: 'Vehicle Brand',
                  hint: 'Toyota',
                  prefixIcon:
                      Icons.directions_car,
                  textInputAction:
                      TextInputAction.next,
                  validator: (value) =>
                      Validators.validateRequired(
                    value,
                    fieldName:
                        'Vehicle Brand',
                  ),
                ),

                const SizedBox(
                  height: AppSpacing.md,
                ),

                AppTextField(
                  controller:
                      _modelController,
                  label: 'Vehicle Model',
                  hint: '2024 Model',
                  prefixIcon:
                      Icons.directions_car,
                  textInputAction:
                      TextInputAction.next,
                  validator: (value) =>
                      Validators.validateRequired(
                    value,
                    fieldName:
                        'Vehicle Model',
                  ),
                ),

                const SizedBox(
                  height: AppSpacing.md,
                ),

                AppTextField(
                  controller:
                      _colorController,
                  label: 'Vehicle Color',
                  hint: 'Blue',
                  prefixIcon:
                      Icons.palette_outlined,
                  textInputAction:
                      TextInputAction.next,
                  validator: (value) =>
                      Validators.validateRequired(
                    value,
                    fieldName:
                        'Vehicle Color',
                  ),
                ),

                const SizedBox(
                  height: AppSpacing.md,
                ),

                AppTextField(
                  controller:
                      _capacityController,
                  label: 'Seating Capacity',
                  hint: '4',
                  prefixIcon:
                      Icons.event_seat_outlined,
                  keyboardType:
                      TextInputType.number,
                  textInputAction:
                      TextInputAction.done,
                  validator: (value) {
                    if (value == null ||
                        value.isEmpty) {
                      return 'Seating capacity is required.';
                    }

                    final seats =
                        int.tryParse(value);

                    if (seats == null ||
                        seats <= 0) {
                      return 'Enter a valid seating capacity.';
                    }

                    return null;
                  },
                  onFieldSubmitted: (_) {
                    _continue();
                  },
                ),

                const SizedBox(
                  height: AppSpacing.xl,
                ),
                                PrimaryButton(
                  text: 'Continue',
                  onPressed: _continue,
                ),

                const SizedBox(
                  height: AppSpacing.lg,
                ),

                TextButton.icon(
                  onPressed: () {
                    context.go(
                      AppRoutes.driverRegisterStep2,
                    );
                  },
                  icon: const Icon(
                    Icons.arrow_back,
                  ),
                  label: const Text(
                    'Back',
                  ),
                ),

                const SizedBox(
                  height: AppSpacing.xl,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}