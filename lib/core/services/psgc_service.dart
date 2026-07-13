import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Philippine Standard Geographic Code (PSGC) Service
///
/// Loads Philippine administrative divisions from local JSON assets.
///
/// Assets required:
/// - assets/regionJson/regions.json
/// - assets/regionJson/provinces.json
/// - assets/regionJson/cities-municipalities.json
/// - assets/regionJson/barangays.json
class PSGCService {
  PSGCService._internal();

  static final PSGCService _instance =
      PSGCService._internal();

  factory PSGCService() => _instance;

  List<Map<String, dynamic>> _regions = [];

  List<Map<String, dynamic>> _provinces = [];

  List<Map<String, dynamic>> _cities = [];

  List<Map<String, dynamic>> _barangays = [];

  bool _initialized = false;

  //==========================================================================
  // Initialize
  //==========================================================================

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    try {
      final regionsJson =
          await rootBundle.loadString(
        'assets/regionJson/regions.json',
      );

      final provincesJson =
          await rootBundle.loadString(
        'assets/regionJson/provinces.json',
      );

      final citiesJson =
          await rootBundle.loadString(
        'assets/regionJson/cities-municipalities.json',
      );

      final barangaysJson =
          await rootBundle.loadString(
        'assets/regionJson/barangays.json',
      );

      _regions = List<Map<String, dynamic>>.from(
        jsonDecode(regionsJson),
      );

      _provinces = List<Map<String, dynamic>>.from(
        jsonDecode(provincesJson),
      );

      _cities = List<Map<String, dynamic>>.from(
        jsonDecode(citiesJson),
      );

      _barangays =
          List<Map<String, dynamic>>.from(
        jsonDecode(barangaysJson),
      );

      _initialized = true;
    } catch (e) {
      debugPrint(
        'PSGC initialization failed: $e',
      );

      rethrow;
    }
  }

  //==========================================================================
  // Collections
  //==========================================================================

  List<Map<String, dynamic>> getRegions() {
    return List.unmodifiable(_regions);
  }

  List<Map<String, dynamic>>
      getProvincesByRegion(
    String regionCode,
  ) {
    return _provinces
        .where(
          (province) =>
              province['regionCode'] ==
              regionCode,
        )
        .toList();
  }

  List<Map<String, dynamic>>
      getCitiesByProvince(
    String provinceCode,
  ) {
    return _cities
        .where(
          (city) =>
              city['provinceCode'] ==
              provinceCode,
        )
        .toList();
  }

  List<Map<String, dynamic>>
      getBarangaysByCity(
    String cityCode,
  ) {
    return _barangays
        .where(
          (barangay) =>
              barangay['cityCode'] ==
                  cityCode ||
              barangay[
                      'municipalityCode'] ==
                  cityCode,
        )
        .toList();
  }

  //==========================================================================
  // Generic Find Helper
  //==========================================================================

  Map<String, dynamic>? _findByName(
    List<Map<String, dynamic>> list,
    String keyword,
  ) {
    final search = keyword
        .toLowerCase()
        .replaceAll('city of', '')
        .trim();

    for (final item in list) {
      final name = item['name']
          .toString()
          .toLowerCase()
          .replaceAll('city of', '')
          .trim();

      if (name.contains(search) ||
          search.contains(name)) {
        return item;
      }
    }

    return null;
  }

  //==========================================================================
  // Find Objects
  //==========================================================================

  Map<String, dynamic>? findRegionByName(
    String name,
  ) {
    return _findByName(
      _regions,
      name,
    );
  }

  Map<String, dynamic>? findProvinceByName(
    String name,
  ) {
    return _findByName(
      _provinces,
      name,
    );
  }

  Map<String, dynamic>? findCityByName(
    String name,
  ) {
    return _findByName(
      _cities,
      name,
    );
  }

  Map<String, dynamic>? findBarangayByName(
    String cityCode,
    String name,
  ) {
    final search = name
        .toLowerCase()
        .replaceAll('barangay', '')
        .replaceAll('brgy.', '')
        .trim();

    for (final barangay in _barangays) {
      final belongsToCity =
          barangay['cityCode'] ==
                  cityCode ||
              barangay[
                      'municipalityCode'] ==
                  cityCode;

      if (!belongsToCity) {
        continue;
      }

      final barangayName =
          barangay['name']
              .toString()
              .toLowerCase()
              .replaceAll(
                'barangay',
                '',
              )
              .replaceAll(
                'brgy.',
                '',
              )
              .trim();

      if (barangayName
              .contains(search) ||
          search.contains(
            barangayName,
          )) {
        return barangay;
      }
    }

    return null;
  }

  //==========================================================================
  // Name Lookup
  //==========================================================================

  String? getRegionName(
    String regionCode,
  ) {
    final matches = _regions.where(
      (region) =>
          region['code'] == regionCode,
    );

    if (matches.isEmpty) {
      return null;
    }

    return matches.first['name']
        as String?;
  }

  String? getProvinceName(
    String provinceCode,
  ) {
    final matches = _provinces.where(
      (province) =>
          province['code'] ==
          provinceCode,
    );

    if (matches.isEmpty) {
      return null;
    }

    return matches.first['name']
        as String?;
  }

  String? getCityName(
    String cityCode,
  ) {
    final matches = _cities.where(
      (city) =>
          city['code'] == cityCode,
    );

    if (matches.isEmpty) {
      return null;
    }

    return matches.first['name']
        as String?;
  }

  String? getBarangayName(
    String barangayCode,
  ) {
    final matches =
        _barangays.where(
      (barangay) =>
          barangay['code'] ==
          barangayCode,
    );

    if (matches.isEmpty) {
      return null;
    }

    return matches.first['name']
        as String?;
  }

  //==========================================================================
  // Helpers
  //==========================================================================

  bool get isInitialized =>
      _initialized;

  int get regionCount =>
      _regions.length;

  int get provinceCount =>
      _provinces.length;

  int get cityCount =>
      _cities.length;

  int get barangayCount =>
      _barangays.length;
}