import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../data/models/app_user.dart';
import '../../../../data/models/passenger.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/passenger_repository.dart';
import '../../../../data/repositories/user_repository.dart';

class EditPassengerProfileScreen extends StatefulWidget {
  const EditPassengerProfileScreen({
    super.key,
  });

  @override
  State<EditPassengerProfileScreen> createState() =>
      _EditPassengerProfileScreenState();
}

class _EditPassengerProfileScreenState
    extends State<EditPassengerProfileScreen> {
  final PassengerRepository _passengerRepository =
      PassengerRepository();

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
    Passenger passenger,
  ) async {
    if (_selectedImage == null) {
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      final photoUrl =
          await _passengerRepository
              .uploadProfilePhoto(
        uid: passenger.uid,
        image: _selectedImage!,
      );

      await _userRepository
          .updateProfileImage(
        uid: passenger.uid,
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
            'Passenger not signed in.',
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

    return StreamBuilder<Passenger?>(
      stream: _passengerRepository
          .passengerStream(
        firebaseUser.uid,
      ),
      builder: (
        context,
        passengerSnapshot,
      ) {
        if (passengerSnapshot
                .connectionState ==
            ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child:
                  CircularProgressIndicator(),
            ),
          );
        }

        if (passengerSnapshot
            .hasError) {
          return Scaffold(
            appBar: AppBar(
              title: const Text(
                'Edit Profile',
              ),
            ),
            body: Center(
              child: Text(
                passengerSnapshot
                    .error
                    .toString(),
              ),
            ),
          );
        }

        final passenger =
            passengerSnapshot.data;

        if (passenger == null) {
          return const Scaffold(
            body: Center(
              child: Text(
                'Passenger profile not found.',
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
                          _selectedImage !=
                                  null
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
                  // Passenger Information
                  //----------------------------------------------------------------

                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(
                            Icons.person,
                          ),
                          title: const Text(
                            'Name',
                          ),
                          subtitle: Text(
                            appUser.fullName,
                          ),
                        ),

                        const Divider(
                          height: 1,
                        ),

                        ListTile(
                          leading: const Icon(
                            Icons.email,
                          ),
                          title: const Text(
                            'Email',
                          ),
                          subtitle: Text(
                            appUser.email,
                          ),
                        ),

                        const Divider(
                          height: 1,
                        ),

                        ListTile(
                          leading: const Icon(
                            Icons.phone,
                          ),
                          title: const Text(
                            'Phone Number',
                          ),
                          subtitle: Text(
                            appUser.phoneNumber,
                          ),
                        ),

                        const Divider(
                          height: 1,
                        ),

                        ListTile(
                          leading: const Icon(
                            Icons.verified_user,
                          ),
                          title: const Text(
                            'Account Status',
                          ),
                          subtitle: Text(
                            appUser.isActive
                                ? 'Active'
                                : 'Inactive',
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
                        : () => _saveProfilePhoto(
                              passenger,
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