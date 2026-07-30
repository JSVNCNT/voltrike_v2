enum PsgcLevel { region, province, city, barangay }

class PsgcCounts {
  const PsgcCounts({
    required this.regions,
    required this.provinces,
    required this.cities,
    required this.barangays,
  });

  static const empty = PsgcCounts(
    regions: 0,
    provinces: 0,
    cities: 0,
    barangays: 0,
  );

  final int regions;
  final int provinces;
  final int cities;
  final int barangays;

  int forLevel(PsgcLevel level) {
    return switch (level) {
      PsgcLevel.region => regions,
      PsgcLevel.province => provinces,
      PsgcLevel.city => cities,
      PsgcLevel.barangay => barangays,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is PsgcCounts &&
        regions == other.regions &&
        provinces == other.provinces &&
        cities == other.cities &&
        barangays == other.barangays;
  }

  @override
  int get hashCode => Object.hash(regions, provinces, cities, barangays);

  @override
  String toString() {
    return 'PsgcCounts('
        'regions: $regions, '
        'provinces: $provinces, '
        'cities: $cities, '
        'barangays: $barangays'
        ')';
  }
}

class PsgcArtifactMetadata {
  const PsgcArtifactMetadata({
    required this.formatVersion,
    required this.artifactBytes,
    required this.payloadBytes,
    required this.payloadChecksumHex,
    required this.stringCount,
    required this.counts,
  });

  final int formatVersion;
  final int artifactBytes;
  final int payloadBytes;
  final String payloadChecksumHex;
  final int stringCount;
  final PsgcCounts counts;

  @override
  bool operator ==(Object other) {
    return other is PsgcArtifactMetadata &&
        formatVersion == other.formatVersion &&
        artifactBytes == other.artifactBytes &&
        payloadBytes == other.payloadBytes &&
        payloadChecksumHex == other.payloadChecksumHex &&
        stringCount == other.stringCount &&
        counts == other.counts;
  }

  @override
  int get hashCode => Object.hash(
    formatVersion,
    artifactBytes,
    payloadBytes,
    payloadChecksumHex,
    stringCount,
    counts,
  );

  @override
  String toString() {
    return 'PsgcArtifactMetadata('
        'formatVersion: $formatVersion, '
        'artifactBytes: $artifactBytes, '
        'payloadBytes: $payloadBytes, '
        'payloadChecksumHex: $payloadChecksumHex, '
        'stringCount: $stringCount, '
        'counts: $counts'
        ')';
  }
}

class PsgcEntry {
  const PsgcEntry({
    required this.level,
    required this.code,
    required this.name,
    required this.islandGroupCode,
    required this.psgc10DigitCode,
    this.regionName,
    this.oldName,
    this.isCapital = false,
    this.isCity = false,
    this.isMunicipality = false,
    this.subMunicipalityCode,
    this.cityCode,
    this.municipalityCode,
    this.districtCode,
    this.provinceCode,
    this.regionCode,
  });

  final PsgcLevel level;
  final String code;
  final String name;
  final String? regionName;
  final String? oldName;
  final bool isCapital;
  final bool isCity;
  final bool isMunicipality;
  final String? subMunicipalityCode;
  final String? cityCode;
  final String? municipalityCode;
  final String? districtCode;
  final String? provinceCode;
  final String? regionCode;
  final String islandGroupCode;
  final String psgc10DigitCode;

  Map<String, dynamic> toLegacyMap() {
    return switch (level) {
      PsgcLevel.region => <String, dynamic>{
        'code': code,
        'name': name,
        'regionName': regionName!,
        'islandGroupCode': islandGroupCode,
        'psgc10DigitCode': psgc10DigitCode,
      },
      PsgcLevel.province => <String, dynamic>{
        'code': code,
        'name': name,
        'regionCode': regionCode!,
        'islandGroupCode': islandGroupCode,
        'psgc10DigitCode': psgc10DigitCode,
      },
      PsgcLevel.city => <String, dynamic>{
        'code': code,
        'name': name,
        'oldName': oldName!,
        'isCapital': isCapital,
        'isCity': isCity,
        'isMunicipality': isMunicipality,
        'provinceCode': provinceCode ?? false,
        'districtCode': districtCode ?? false,
        'regionCode': regionCode!,
        'islandGroupCode': islandGroupCode,
        'psgc10DigitCode': psgc10DigitCode,
      },
      PsgcLevel.barangay => <String, dynamic>{
        'code': code,
        'name': name,
        'oldName': oldName!,
        'subMunicipalityCode': subMunicipalityCode ?? false,
        'cityCode': cityCode ?? false,
        'municipalityCode': municipalityCode ?? false,
        'districtCode': districtCode ?? false,
        'provinceCode': provinceCode ?? false,
        'regionCode': regionCode!,
        'islandGroupCode': islandGroupCode,
        'psgc10DigitCode': psgc10DigitCode,
      },
    };
  }
}

String normalizePsgcName(String value) {
  return value.toLowerCase().replaceAll('city of', '').trim();
}

String normalizePsgcBarangayName(String value) {
  return value
      .toLowerCase()
      .replaceAll('barangay', '')
      .replaceAll('brgy.', '')
      .trim();
}
