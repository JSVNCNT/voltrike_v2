import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../data/models/app_user.dart';
import '../../../../data/models/driver.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/driver_repository.dart';
import '../../../../data/repositories/user_repository.dart';

class EditDriverProfileScreen extends StatefulWidget {
  const EditDriverProfileScreen({
    super.key,
  });

  @override
  State<EditDriverProfileScreen> createState() =>
      _EditDriverProfileScreenState();
}

class _EditDriverProfileScreenState
    extends State<EditDriverProfileScreen> {
  final DriverRepository _driverRepository =
      DriverRepository();

  final UserRepository _userRepository =
      UserRepository();

  final AuthRepository _authRepository =
      AuthRepository();

  final ImagePicker _imagePicker =
      ImagePicker();

  File? _selectedImage;

  bool _isUploading = false;

  //==========================================================================
  // Pick Image
  //==========================================================================

  Future<void> _pickImage() async {
    final file =
        await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );

    if (file == null) {
      return;
    }

    setState(() {
      _selectedImage = File(file.path);
    });
  }

  //==========================================================================
  // Upload Profile Photo
  //==========================================================================

  Future<void> _saveProfilePhoto(
    Driver driver,
  ) async {
    if (_selectedImage == null) {
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      final photoUrl =
          await _driverRepository
              .uploadProfilePhoto(
        uid: driver.uid,
        image: _selectedImage!,
      );

      await _userRepository
          .updateProfileImage(
        uid: driver.uid,
        photoUrl: photoUrl,
      );

      if (!mounted) {
        return;
      }

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            e.toString(),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
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
    final firebaseUser =
        _authRepository.currentUser;

    if (firebaseUser == null) {
      return const Scaffold(
        body: Center(
          child: Text(
            'Driver not signed in.',
          ),
        ),
      );
    }

    return StreamBuilder<AppUser?>(
      stream: _userRepository.userStream(
        firebaseUser.uid,
      ),
      builder: (
        context,
        userSnapshot,
      ) {
        if (userSnapshot.connectionState ==
            ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child:
                  CircularProgressIndicator(),
            ),
          );
        }

        if (userSnapshot.hasError) {
          return Scaffold(
            appBar: AppBar(
              title: const Text(
                'Edit Profile',
              ),
            ),
            body: Center(
              child: Text(
                userSnapshot.error
                    .toString(),
              ),
            ),
          );
        }

        final appUser =
            userSnapshot.data;

        if (appUser == null) {
          return const Scaffold(
            body: Center(
              child: Text(
                'User profile not found.',
              ),
            ),
          );
        }

        return StreamBuilder<Driver?>(
  stream: _driverRepository.driverStream(
    firebaseUser.uid,
  ),
  builder: (
    context,
    driverSnapshot,
  ) {
    if (driverSnapshot.connectionState ==
        ConnectionState.waiting) {
      return const Scaffold(
        body: Center(
          child:
              CircularProgressIndicator(),
        ),
      );
    }

    if (driverSnapshot.hasError) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Edit Profile',
          ),
        ),
        body: Center(
          child: Text(
            driverSnapshot.error
                .toString(),
          ),
        ),
      );
    }

    final driver =
        driverSnapshot.data;

    if (driver == null) {
      return const Scaffold(
        body: Center(
          child: Text(
            'Driver profile not found.',
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Edit Profile',
        ),
      ),
      body: SafeArea(
        child:
            SingleChildScrollView(
          padding:
              const EdgeInsets.all(
            16,
          ),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment
                    .stretch,
            children: [
              //----------------------------------------------------------------
              // Profile Photo
              //----------------------------------------------------------------

              Center(
                child: CircleAvatar(
                  radius: 65,
                  backgroundImage:
                      _selectedImage != null
                          ? FileImage(
                              _selectedImage!,
                            )
                          : appUser
                                  .profileImage
                                  .isNotEmpty
                              ? NetworkImage(
                                  appUser
                                      .profileImage,
                                )
                              : null,
                  child: _selectedImage ==
                              null &&
                          appUser
                              .profileImage
                              .isEmpty
                      ? const Icon(
                          Icons.person,
                          size: 65,
                        )
                      : null,
                ),
              ),

              const SizedBox(
                height: 16,
              ),

              Center(
                child:
                    OutlinedButton.icon(
                  onPressed:
                      _isUploading
                          ? null
                          : _pickImage,
                  icon: const Icon(
                    Icons
                        .photo_camera_outlined,
                  ),
                  label: const Text(
                    'Change Photo',
                  ),
                ),
              ),

              const SizedBox(
                height: 32,
              ),

                            //----------------------------------------------------------------
              // Driver Information
              //----------------------------------------------------------------

              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(
                        Icons.groups,
                      ),
                      title: const Text(
                        'TODA ID',
                      ),
                      subtitle: Text(
                        driver.todaId,
                      ),
                    ),

                    const Divider(
                      height: 1,
                    ),

                    ListTile(
                      leading: const Icon(
                        Icons.directions_car,
                      ),
                      title: const Text(
                        'Vehicle ID',
                      ),
                      subtitle: Text(
                        driver.vehicleId,
                      ),
                    ),

                    const Divider(
                      height: 1,
                    ),

                    ListTile(
                      leading: const Icon(
                        Icons.badge,
                      ),
                      title: const Text(
                        'License Number',
                      ),
                      subtitle: Text(
                        driver.licenseNumber,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(
                height: 32,
              ),

              //----------------------------------------------------------------
              // Save Button
              //----------------------------------------------------------------

              FilledButton.icon(
                onPressed: _isUploading
                    ? null
                    : () =>
                        _saveProfilePhoto(
                          driver,
                        ),
                icon: _isUploading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child:
                            CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(
                        Icons.save,
                      ),
                label: Text(
                  _isUploading
                      ? 'Uploading...'
                      : 'Save Photo',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  },
);
      },
    );
  }
}