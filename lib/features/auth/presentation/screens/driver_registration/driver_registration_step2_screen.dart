import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/routes.dart';
import '../../../../../core/services/psgc_service.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/utils/validators.dart';
import '../../../../../core/widgets/buttons/primary_button.dart';
import '../../../../../core/widgets/inputs/app_text_field.dart';

import '../../../../../data/models/toda.dart';

import '../../providers/auth_provider.dart';
import '../../providers/driver_registration_data_provider.dart';

import '../../widgets/auth_header.dart';
import '../../widgets/auth_logo.dart';
import '../../widgets/auth_scaffold.dart';
import '../../widgets/loading_overlay.dart';
import '../../widgets/validation_message.dart';

class DriverRegistrationStep2Screen
    extends ConsumerStatefulWidget {
  const DriverRegistrationStep2Screen({
    super.key,
  });

  @override
  ConsumerState<DriverRegistrationStep2Screen>
      createState() =>
          _DriverRegistrationStep2ScreenState();
}

class _DriverRegistrationStep2ScreenState
    extends ConsumerState<
        DriverRegistrationStep2Screen> {
  final _formKey =
      GlobalKey<FormState>();

  final _licenseController =
      TextEditingController();

  final PSGCService _locationService =
      PSGCService();

  bool _loading = true;

  String? _error;

  DateTime? _licenseExpiry;

  String? _selectedRegion;
  String? _selectedProvince;
  String? _selectedCity;
  String? _selectedBarangay;
  String? _selectedToda;

  List<Map<String, dynamic>>
      _regions = [];

  List<Map<String, dynamic>>
      _provinces = [];

  List<Map<String, dynamic>>
      _cities = [];

  List<Map<String, dynamic>>
      _barangays = [];

  final List<Toda> _todas = [];

  @override
  void initState() {
    super.initState();

    final registration = ref.read(
      driverRegistrationDataProvider,
    );

    _licenseController.text =
        registration.licenseNumber;

    _licenseExpiry =
        registration.licenseExpiry;

    _selectedRegion =
        registration.region!.isEmpty
            ? null
            : registration.region;

    _selectedProvince =
        registration.province!.isEmpty
            ? null
            : registration.province;

    _selectedCity =
        registration.city!.isEmpty
            ? null
            : registration.city;

    _selectedBarangay =
        registration.barangay!.isEmpty
            ? null
            : registration.barangay;

    _selectedToda =
        registration.todaId.isEmpty
            ? null
            : registration.todaId;

    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _locationService.initialize();

      _regions =
          _locationService.getRegions();

      if (_selectedRegion != null) {
        _provinces =
            _locationService
                .getProvincesByRegion(
          _selectedRegion!,
        );
      }

      if (_selectedProvince != null) {
        _cities =
            _locationService
                .getCitiesByProvince(
          _selectedProvince!,
        );
      }

      if (_selectedCity != null) {
        _barangays =
            _locationService
                .getBarangaysByCity(
          _selectedCity!,
        );
      }

      // Load ALL active TODAs
      await _loadTodas();

      if (_selectedToda != null &&
          !_todas.any(
            (e) =>
                e.id ==
                _selectedToda,
          )) {
        _selectedToda = null;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _pickExpiryDate() async {
  final picked = await showDatePicker(
    context: context,
    initialDate:
        _licenseExpiry ??
            DateTime.now(),
    firstDate: DateTime.now(),
    lastDate: DateTime(2100),
  );

  if (picked == null) {
    return;
  }

  setState(() {
    _licenseExpiry = picked;
  });
}

void _onRegionChanged(
  String? value,
) {
  setState(() {
    _selectedRegion = value;

    _selectedProvince = null;
    _selectedCity = null;
    _selectedBarangay = null;
    _selectedToda = null;

    _provinces = value == null
        ? []
        : _locationService
            .getProvincesByRegion(
              value,
            );

    _cities = [];
    _barangays = [];
  });
}

void _onProvinceChanged(
  String? value,
) {
  setState(() {
    _selectedProvince = value;

    _selectedCity = null;
    _selectedBarangay = null;
    _selectedToda = null;

    _cities = value == null
        ? []
        : _locationService
            .getCitiesByProvince(
              value,
            );

    _barangays = [];
  });
}

void _onCityChanged(
  String? value,
) {
  setState(() {
    _selectedCity = value;

    _selectedBarangay = null;
    _selectedToda = null;

    _barangays = value == null
        ? []
        : _locationService
            .getBarangaysByCity(
              value,
            );
  });
}

void _onBarangayChanged(
  String? value,
) {
  setState(() {
    _selectedBarangay = value;

    // Keep TODAs loaded globally.
    _selectedToda = null;
  });
}
void _continue() {
  if (!_formKey.currentState!.validate()) {
    return;
  }

  if (_licenseExpiry == null) {
    setState(() {
      _error =
          'Please select your license expiration date.';
    });

    return;
  }

  if (_selectedRegion == null ||
      _selectedProvince == null ||
      _selectedCity == null ||
      _selectedBarangay == null ||
      _selectedToda == null) {
    setState(() {
      _error =
          'Please complete all required fields.';
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
        licenseNumber:
            _licenseController.text.trim(),
        licenseExpiry:
            _licenseExpiry,
        region: _selectedRegion!,
        province:
            _selectedProvince!,
        city: _selectedCity!,
        barangay:
            _selectedBarangay!,
        todaId:
            _selectedToda!,
      );

  context.go(
    AppRoutes.driverRegisterStep3,
  );
}

@override
void dispose() {
  _licenseController.dispose();
  super.dispose();
}
@override
Widget build(BuildContext context) {
  return LoadingOverlay(
    isLoading: _loading,
    child: AuthScaffold(
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              const SizedBox(
                height: AppSpacing.lg,
              ),

              const AuthLogo(),

              const SizedBox(
                height: AppSpacing.xl,
              ),

              const AuthHeader(
                title: 'Driver Registration',
                subtitle:
                    'Step 2 of 4\nLicense & Address',
              ),

              const SizedBox(
                height: AppSpacing.xl,
              ),

              if (_error != null) ...[
                ValidationMessage(
                  message: _error!,
                ),
                const SizedBox(
                  height: AppSpacing.md,
                ),
              ],

              AppTextField(
                controller: _licenseController,
                label: 'Driver License Number',
                validator: Validators.required,
              ),

              const SizedBox(
                height: AppSpacing.md,
              ),

              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _licenseExpiry == null
                      ? 'Select License Expiration'
                      : 'Expires: ${_licenseExpiry!.toLocal().toString().split(' ')[0]}',
                ),
                trailing: const Icon(
                  Icons.calendar_month,
                ),
                onTap: _pickExpiryDate,
              ),

              const SizedBox(
                height: AppSpacing.lg,
              ),

              DropdownButtonFormField<String>(
                initialValue:
                    _regions.any(
                      (e) =>
                          e['code'] ==
                          _selectedRegion,
                    )
                        ? _selectedRegion
                        : null,
                decoration:
                    const InputDecoration(
                  labelText: 'Region',
                ),
                items: _regions
                    .map(
                      (region) =>
                          DropdownMenuItem<String>(
                        value:
                            region['code']
                                as String,
                        child: Text(
                          region['name']
                              as String,
                        ),
                      ),
                    )
                    .toList(),
                onChanged:
                    _onRegionChanged,
                validator: (value) =>
                    value == null
                        ? 'Required'
                        : null,
              ),

              const SizedBox(
                height: AppSpacing.md,
              ),

              DropdownButtonFormField<String>(
                initialValue:
                    _provinces.any(
                      (e) =>
                          e['code'] ==
                          _selectedProvince,
                    )
                        ? _selectedProvince
                        : null,
                decoration:
                    const InputDecoration(
                  labelText:
                      'Province',
                ),
                items: _provinces
                    .map(
                      (province) =>
                          DropdownMenuItem<String>(
                        value:
                            province['code']
                                as String,
                        child: Text(
                          province['name']
                              as String,
                        ),
                      ),
                    )
                    .toList(),
                onChanged:
                    _selectedRegion == null
                        ? null
                        : _onProvinceChanged,
                validator: (value) =>
                    value == null
                        ? 'Required'
                        : null,
              ),

              const SizedBox(
                height: AppSpacing.md,
              ),

              DropdownButtonFormField<String>(
                initialValue:
                    _cities.any(
                      (e) =>
                          e['code'] ==
                          _selectedCity,
                    )
                        ? _selectedCity
                        : null,
                decoration:
                    const InputDecoration(
                  labelText:
                      'City / Municipality',
                ),
                items: _cities
                    .map(
                      (city) =>
                          DropdownMenuItem<String>(
                        value:
                            city['code']
                                as String,
                        child: Text(
                          city['name']
                              as String,
                        ),
                      ),
                    )
                    .toList(),
                onChanged:
                    _selectedProvince ==
                            null
                        ? null
                        : _onCityChanged,
                validator: (value) =>
                    value == null
                        ? 'Required'
                        : null,
              ),

              const SizedBox(
                height: AppSpacing.md,
              ),

              DropdownButtonFormField<String>(
                initialValue:
                    _barangays.any(
                      (e) =>
                          e['code'] ==
                          _selectedBarangay,
                    )
                        ? _selectedBarangay
                        : null,
                decoration:
                    const InputDecoration(
                  labelText:
                      'Barangay',
                ),
                items: _barangays
                    .map(
                      (barangay) =>
                          DropdownMenuItem<String>(
                        value:
                            barangay['code']
                                as String,
                        child: Text(
                          barangay['name']
                              as String,
                        ),
                      ),
                    )
                    .toList(),
                onChanged:
                    _selectedCity == null
                        ? null
                        : _onBarangayChanged,
                validator: (value) =>
                    value == null
                        ? 'Required'
                        : null,
              ),

              const SizedBox(
                height: AppSpacing.md,
              ),
              DropdownButtonFormField<String>(
  initialValue: _todas.any(
          (toda) =>
              toda.id ==
              _selectedToda)
      ? _selectedToda
      : null,
  decoration:
      const InputDecoration(
    labelText: 'TODA',
  ),
  items: _todas
      .map(
        (toda) =>
            DropdownMenuItem<String>(
          value: toda.id,
          child: Text(
            toda.name,
          ),
        ),
      )
      .toList(),

  // TODAs are no longer filtered by barangay.
  onChanged: (value) {
    setState(() {
      _selectedToda = value;
    });
  },

  validator: (value) =>
      value == null
          ? 'Please select a TODA.'
          : null,
),

const SizedBox(
  height: AppSpacing.xl,
),

PrimaryButton(
  text: 'Continue',
  onPressed: _continue,
),

const SizedBox(
  height: AppSpacing.md,
),

TextButton.icon(
  onPressed: () {
    context.go(
      AppRoutes.driverRegisterStep1,
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
  height: AppSpacing.xxl,
),
            ],
          ),
        ),
      ),
    ),
  );
}

  Future<void> _loadTodas() async {
    final repository = ref.read(
    todaRepositoryProvider,
  );

  _todas.clear();

  _todas.addAll(
    await repository.getAllActiveTodas(),
  );
  }
}