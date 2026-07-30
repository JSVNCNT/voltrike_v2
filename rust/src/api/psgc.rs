use std::collections::HashMap;
use std::sync::{OnceLock, RwLock};

const MAGIC: &[u8; 8] = b"VPSGCIDX";
const FORMAT_VERSION: u32 = 1;
const HEADER_LENGTH: usize = 44;
const MISSING_STRING: u32 = u32::MAX;
const FNV_OFFSET_BASIS: u64 = 0xcbf29ce484222325;
const FNV_PRIME: u64 = 0x100000001b3;
const MAX_ARTIFACT_BYTES: usize = 16 * 1024 * 1024;
const MAX_STRINGS: usize = 500_000;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum PsgcLevel {
    Region,
    Province,
    City,
    Barangay,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PsgcOperationStatus {
    Ok,
    InvalidArtifact,
    NotInitialized,
    InternalError,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct PsgcCounts {
    pub regions: u32,
    pub provinces: u32,
    pub cities: u32,
    pub barangays: u32,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PsgcEntry {
    pub level: PsgcLevel,
    pub code: String,
    pub name: String,
    pub region_name: Option<String>,
    pub old_name: Option<String>,
    pub is_capital: bool,
    pub is_city: bool,
    pub is_municipality: bool,
    pub sub_municipality_code: Option<String>,
    pub city_code: Option<String>,
    pub municipality_code: Option<String>,
    pub district_code: Option<String>,
    pub province_code: Option<String>,
    pub region_code: Option<String>,
    pub island_group_code: String,
    pub psgc10_digit_code: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PsgcInitializationResult {
    pub status: PsgcOperationStatus,
    pub counts: PsgcCounts,
    pub format_version: u32,
    pub artifact_bytes: u32,
    pub payload_bytes: u32,
    pub payload_checksum_hex: String,
    pub string_count: u32,
    pub error_message: Option<String>,
}

impl PsgcInitializationResult {
    fn ok(index: &PsgcIndex, counts: PsgcCounts) -> Result<Self, String> {
        let artifact_bytes = u32::try_from(index.artifact_bytes)
            .map_err(|_| "artifact byte count does not fit into u32".to_owned())?;
        let string_count = u32::try_from(index.strings.len())
            .map_err(|_| "string count does not fit into u32".to_owned())?;
        Ok(Self {
            status: PsgcOperationStatus::Ok,
            counts,
            format_version: FORMAT_VERSION,
            artifact_bytes,
            payload_bytes: index.payload_bytes,
            payload_checksum_hex: format!("{:016x}", index.payload_checksum),
            string_count,
            error_message: None,
        })
    }

    fn error(status: PsgcOperationStatus, message: impl Into<String>) -> Self {
        Self {
            status,
            counts: PsgcCounts::default(),
            format_version: 0,
            artifact_bytes: 0,
            payload_bytes: 0,
            payload_checksum_hex: String::new(),
            string_count: 0,
            error_message: Some(message.into()),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PsgcQueryResult {
    pub status: PsgcOperationStatus,
    pub entries: Vec<PsgcEntry>,
    pub error_message: Option<String>,
}

impl PsgcQueryResult {
    fn ok(entries: Vec<PsgcEntry>) -> Self {
        Self {
            status: PsgcOperationStatus::Ok,
            entries,
            error_message: None,
        }
    }

    fn error(status: PsgcOperationStatus, message: impl Into<String>) -> Self {
        Self {
            status,
            entries: Vec::new(),
            error_message: Some(message.into()),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PsgcLookupResult {
    pub status: PsgcOperationStatus,
    pub entry: Option<PsgcEntry>,
    pub error_message: Option<String>,
}

impl PsgcLookupResult {
    fn ok(entry: Option<PsgcEntry>) -> Self {
        Self {
            status: PsgcOperationStatus::Ok,
            entry,
            error_message: None,
        }
    }

    fn error(status: PsgcOperationStatus, message: impl Into<String>) -> Self {
        Self {
            status,
            entry: None,
            error_message: Some(message.into()),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PsgcNameResult {
    pub status: PsgcOperationStatus,
    pub name: Option<String>,
    pub error_message: Option<String>,
}

impl PsgcNameResult {
    fn ok(name: Option<String>) -> Self {
        Self {
            status: PsgcOperationStatus::Ok,
            name,
            error_message: None,
        }
    }

    fn error(status: PsgcOperationStatus, message: impl Into<String>) -> Self {
        Self {
            status,
            name: None,
            error_message: Some(message.into()),
        }
    }
}

#[derive(Clone, Copy, Debug)]
struct RegionRow {
    code: u32,
    name: u32,
    region_name: u32,
    island_group_code: u32,
    psgc10_digit_code: u32,
}

#[derive(Clone, Copy, Debug)]
struct ProvinceRow {
    code: u32,
    name: u32,
    region_code: u32,
    island_group_code: u32,
    psgc10_digit_code: u32,
}

#[derive(Clone, Copy, Debug)]
struct CityRow {
    code: u32,
    name: u32,
    old_name: u32,
    flags: u8,
    province_code: u32,
    district_code: u32,
    region_code: u32,
    island_group_code: u32,
    psgc10_digit_code: u32,
}

#[derive(Clone, Copy, Debug)]
struct BarangayRow {
    code: u32,
    name: u32,
    old_name: u32,
    sub_municipality_code: u32,
    city_code: u32,
    municipality_code: u32,
    district_code: u32,
    province_code: u32,
    region_code: u32,
    island_group_code: u32,
    psgc10_digit_code: u32,
}

#[derive(Clone, Copy, Debug)]
struct ArtifactMetadata {
    artifact_bytes: usize,
    payload_bytes: u32,
    payload_checksum: u64,
}

struct PsgcIndex {
    artifact_bytes: usize,
    payload_bytes: u32,
    payload_checksum: u64,
    strings: Vec<String>,
    regions: Vec<RegionRow>,
    provinces: Vec<ProvinceRow>,
    cities: Vec<CityRow>,
    barangays: Vec<BarangayRow>,
    provinces_by_region: HashMap<u32, Vec<usize>>,
    cities_by_province: HashMap<u32, Vec<usize>>,
    barangays_by_city: HashMap<u32, Vec<usize>>,
    regions_by_code: HashMap<u32, usize>,
    provinces_by_code: HashMap<u32, usize>,
    cities_by_code: HashMap<u32, usize>,
    barangays_by_code: HashMap<u32, usize>,
}

impl PsgcIndex {
    fn parse(bytes: &[u8]) -> Result<Self, String> {
        if bytes.len() < HEADER_LENGTH {
            return Err("PSGC artifact header is truncated".to_owned());
        }
        if bytes.len() > MAX_ARTIFACT_BYTES {
            return Err("PSGC artifact exceeds the size limit".to_owned());
        }
        if bytes.get(..MAGIC.len()) != Some(MAGIC.as_slice()) {
            return Err("PSGC artifact magic is invalid".to_owned());
        }

        let mut header = Cursor::new(bytes, MAGIC.len());
        let version = header.read_u32()?;
        if version != FORMAT_VERSION {
            return Err(format!("unsupported PSGC artifact version {version}"));
        }
        let payload_length = header.read_u32()? as usize;
        let expected_checksum = header.read_u64()?;
        let region_count = header.read_u32()? as usize;
        let province_count = header.read_u32()? as usize;
        let city_count = header.read_u32()? as usize;
        let barangay_count = header.read_u32()? as usize;
        let string_count = header.read_u32()? as usize;

        if payload_length != bytes.len() - HEADER_LENGTH {
            return Err("PSGC artifact length is invalid".to_owned());
        }
        if fnv1a(&bytes[HEADER_LENGTH..]) != expected_checksum {
            return Err("PSGC artifact checksum is invalid".to_owned());
        }
        validate_counts(
            region_count,
            province_count,
            city_count,
            barangay_count,
            string_count,
        )?;

        let mut reader = Cursor::new(bytes, HEADER_LENGTH);
        let mut strings = Vec::with_capacity(string_count);
        for _ in 0..string_count {
            strings.push(reader.read_string()?);
        }

        let mut regions = Vec::with_capacity(region_count);
        for _ in 0..region_count {
            regions.push(RegionRow {
                code: read_required_id(&mut reader, string_count)?,
                name: read_required_id(&mut reader, string_count)?,
                region_name: read_required_id(&mut reader, string_count)?,
                island_group_code: read_required_id(&mut reader, string_count)?,
                psgc10_digit_code: read_required_id(&mut reader, string_count)?,
            });
        }

        let mut provinces = Vec::with_capacity(province_count);
        for _ in 0..province_count {
            provinces.push(ProvinceRow {
                code: read_required_id(&mut reader, string_count)?,
                name: read_required_id(&mut reader, string_count)?,
                region_code: read_required_id(&mut reader, string_count)?,
                island_group_code: read_required_id(&mut reader, string_count)?,
                psgc10_digit_code: read_required_id(&mut reader, string_count)?,
            });
        }

        let mut cities = Vec::with_capacity(city_count);
        for _ in 0..city_count {
            let code = read_required_id(&mut reader, string_count)?;
            let name = read_required_id(&mut reader, string_count)?;
            let old_name = read_required_id(&mut reader, string_count)?;
            let flags = reader.read_u8()?;
            if flags & !7 != 0 {
                return Err("PSGC city flags are invalid".to_owned());
            }
            cities.push(CityRow {
                code,
                name,
                old_name,
                flags,
                province_code: read_optional_id(&mut reader, string_count)?,
                district_code: read_optional_id(&mut reader, string_count)?,
                region_code: read_required_id(&mut reader, string_count)?,
                island_group_code: read_required_id(&mut reader, string_count)?,
                psgc10_digit_code: read_required_id(&mut reader, string_count)?,
            });
        }

        let mut barangays = Vec::with_capacity(barangay_count);
        for _ in 0..barangay_count {
            barangays.push(BarangayRow {
                code: read_required_id(&mut reader, string_count)?,
                name: read_required_id(&mut reader, string_count)?,
                old_name: read_required_id(&mut reader, string_count)?,
                sub_municipality_code: read_optional_id(&mut reader, string_count)?,
                city_code: read_optional_id(&mut reader, string_count)?,
                municipality_code: read_optional_id(&mut reader, string_count)?,
                district_code: read_optional_id(&mut reader, string_count)?,
                province_code: read_optional_id(&mut reader, string_count)?,
                region_code: read_required_id(&mut reader, string_count)?,
                island_group_code: read_required_id(&mut reader, string_count)?,
                psgc10_digit_code: read_required_id(&mut reader, string_count)?,
            });
        }
        if !reader.is_at_end() {
            return Err("PSGC artifact contains trailing bytes".to_owned());
        }

        let metadata = ArtifactMetadata {
            artifact_bytes: bytes.len(),
            payload_bytes: u32::try_from(payload_length)
                .map_err(|_| "payload byte count does not fit into u32".to_owned())?,
            payload_checksum: expected_checksum,
        };
        Self::build(metadata, strings, regions, provinces, cities, barangays)
    }

    fn build(
        metadata: ArtifactMetadata,
        strings: Vec<String>,
        regions: Vec<RegionRow>,
        provinces: Vec<ProvinceRow>,
        cities: Vec<CityRow>,
        barangays: Vec<BarangayRow>,
    ) -> Result<Self, String> {
        let mut index = Self {
            artifact_bytes: metadata.artifact_bytes,
            payload_bytes: metadata.payload_bytes,
            payload_checksum: metadata.payload_checksum,
            strings,
            regions,
            provinces,
            cities,
            barangays,
            provinces_by_region: HashMap::new(),
            cities_by_province: HashMap::new(),
            barangays_by_city: HashMap::new(),
            regions_by_code: HashMap::new(),
            provinces_by_code: HashMap::new(),
            cities_by_code: HashMap::new(),
            barangays_by_code: HashMap::new(),
        };

        for (position, row) in index.regions.iter().enumerate() {
            let code = index.numeric_id(row.code, "region code")?;
            index.regions_by_code.entry(code).or_insert(position);
        }
        for (position, row) in index.provinces.iter().enumerate() {
            let code = index.numeric_id(row.code, "province code")?;
            let parent = index.numeric_id(row.region_code, "province region code")?;
            index.provinces_by_code.entry(code).or_insert(position);
            index
                .provinces_by_region
                .entry(parent)
                .or_default()
                .push(position);
        }
        for (position, row) in index.cities.iter().enumerate() {
            let code = index.numeric_id(row.code, "city code")?;
            index.cities_by_code.entry(code).or_insert(position);
            if let Some(parent) =
                index.optional_numeric_id(row.province_code, "city province code")?
            {
                index
                    .cities_by_province
                    .entry(parent)
                    .or_default()
                    .push(position);
            }
        }
        for (position, row) in index.barangays.iter().enumerate() {
            let code = index.numeric_id(row.code, "barangay code")?;
            index.barangays_by_code.entry(code).or_insert(position);
            let city = index.optional_numeric_id(row.city_code, "barangay city code")?;
            let municipality =
                index.optional_numeric_id(row.municipality_code, "barangay municipality code")?;
            if let Some(parent) = city {
                index
                    .barangays_by_city
                    .entry(parent)
                    .or_default()
                    .push(position);
            }
            if let Some(parent) = municipality {
                if Some(parent) != city {
                    index
                        .barangays_by_city
                        .entry(parent)
                        .or_default()
                        .push(position);
                }
            }
        }
        Ok(index)
    }

    fn counts(&self) -> Result<PsgcCounts, String> {
        Ok(PsgcCounts {
            regions: u32::try_from(self.regions.len())
                .map_err(|_| "region count does not fit into u32".to_owned())?,
            provinces: u32::try_from(self.provinces.len())
                .map_err(|_| "province count does not fit into u32".to_owned())?,
            cities: u32::try_from(self.cities.len())
                .map_err(|_| "city count does not fit into u32".to_owned())?,
            barangays: u32::try_from(self.barangays.len())
                .map_err(|_| "barangay count does not fit into u32".to_owned())?,
        })
    }

    fn query(&self, level: PsgcLevel, parent_code: Option<&str>) -> Result<Vec<PsgcEntry>, String> {
        match level {
            PsgcLevel::Region => (0..self.regions.len())
                .map(|position| self.entry_at(level, position))
                .collect(),
            PsgcLevel::Province => {
                self.entries_for_parent(level, parent_code, &self.provinces_by_region)
            }
            PsgcLevel::City => {
                self.entries_for_parent(level, parent_code, &self.cities_by_province)
            }
            PsgcLevel::Barangay => {
                self.entries_for_parent(level, parent_code, &self.barangays_by_city)
            }
        }
    }

    fn entries_for_parent(
        &self,
        level: PsgcLevel,
        parent_code: Option<&str>,
        groups: &HashMap<u32, Vec<usize>>,
    ) -> Result<Vec<PsgcEntry>, String> {
        let Some(parent) = parent_code.and_then(parse_code) else {
            return Ok(Vec::new());
        };
        let Some(positions) = groups.get(&parent) else {
            return Ok(Vec::new());
        };
        positions
            .iter()
            .map(|position| self.entry_at(level, *position))
            .collect()
    }

    fn find_by_name(
        &self,
        level: PsgcLevel,
        parent_code: Option<&str>,
        name: &str,
    ) -> Result<Option<PsgcEntry>, String> {
        let search = normalize_name(level, name);
        match level {
            PsgcLevel::Region => self.find_in_positions(level, 0..self.regions.len(), &search),
            PsgcLevel::Province => self.find_in_positions(level, 0..self.provinces.len(), &search),
            PsgcLevel::City => self.find_in_positions(level, 0..self.cities.len(), &search),
            PsgcLevel::Barangay => {
                let Some(parent) = parent_code.and_then(parse_code) else {
                    return Ok(None);
                };
                let positions = self
                    .barangays_by_city
                    .get(&parent)
                    .map(Vec::as_slice)
                    .unwrap_or_default();
                self.find_in_positions(level, positions.iter().copied(), &search)
            }
        }
    }

    fn find_in_positions<I>(
        &self,
        level: PsgcLevel,
        positions: I,
        search: &str,
    ) -> Result<Option<PsgcEntry>, String>
    where
        I: IntoIterator<Item = usize>,
    {
        for position in positions {
            let entry = self.entry_at(level, position)?;
            let candidate = normalize_name(level, &entry.name);
            if candidate.contains(search) || search.contains(&candidate) {
                return Ok(Some(entry));
            }
        }
        Ok(None)
    }

    fn name_for_code(&self, level: PsgcLevel, code: &str) -> Result<Option<String>, String> {
        let Some(code) = parse_code(code) else {
            return Ok(None);
        };
        let position = match level {
            PsgcLevel::Region => self.regions_by_code.get(&code),
            PsgcLevel::Province => self.provinces_by_code.get(&code),
            PsgcLevel::City => self.cities_by_code.get(&code),
            PsgcLevel::Barangay => self.barangays_by_code.get(&code),
        };
        position
            .map(|position| self.entry_at(level, *position).map(|entry| entry.name))
            .transpose()
    }

    fn entry_at(&self, level: PsgcLevel, position: usize) -> Result<PsgcEntry, String> {
        match level {
            PsgcLevel::Region => {
                let row = self
                    .regions
                    .get(position)
                    .ok_or_else(|| "region index is out of bounds".to_owned())?;
                Ok(PsgcEntry {
                    level,
                    code: self.string(row.code)?.to_owned(),
                    name: self.string(row.name)?.to_owned(),
                    region_name: Some(self.string(row.region_name)?.to_owned()),
                    old_name: None,
                    is_capital: false,
                    is_city: false,
                    is_municipality: false,
                    sub_municipality_code: None,
                    city_code: None,
                    municipality_code: None,
                    district_code: None,
                    province_code: None,
                    region_code: None,
                    island_group_code: self.string(row.island_group_code)?.to_owned(),
                    psgc10_digit_code: self.string(row.psgc10_digit_code)?.to_owned(),
                })
            }
            PsgcLevel::Province => {
                let row = self
                    .provinces
                    .get(position)
                    .ok_or_else(|| "province index is out of bounds".to_owned())?;
                Ok(PsgcEntry {
                    level,
                    code: self.string(row.code)?.to_owned(),
                    name: self.string(row.name)?.to_owned(),
                    region_name: None,
                    old_name: None,
                    is_capital: false,
                    is_city: false,
                    is_municipality: false,
                    sub_municipality_code: None,
                    city_code: None,
                    municipality_code: None,
                    district_code: None,
                    province_code: None,
                    region_code: Some(self.string(row.region_code)?.to_owned()),
                    island_group_code: self.string(row.island_group_code)?.to_owned(),
                    psgc10_digit_code: self.string(row.psgc10_digit_code)?.to_owned(),
                })
            }
            PsgcLevel::City => {
                let row = self
                    .cities
                    .get(position)
                    .ok_or_else(|| "city index is out of bounds".to_owned())?;
                Ok(PsgcEntry {
                    level,
                    code: self.string(row.code)?.to_owned(),
                    name: self.string(row.name)?.to_owned(),
                    region_name: None,
                    old_name: Some(self.string(row.old_name)?.to_owned()),
                    is_capital: row.flags & 1 != 0,
                    is_city: row.flags & 2 != 0,
                    is_municipality: row.flags & 4 != 0,
                    sub_municipality_code: None,
                    city_code: None,
                    municipality_code: None,
                    district_code: self.optional_string(row.district_code)?,
                    province_code: self.optional_string(row.province_code)?,
                    region_code: Some(self.string(row.region_code)?.to_owned()),
                    island_group_code: self.string(row.island_group_code)?.to_owned(),
                    psgc10_digit_code: self.string(row.psgc10_digit_code)?.to_owned(),
                })
            }
            PsgcLevel::Barangay => {
                let row = self
                    .barangays
                    .get(position)
                    .ok_or_else(|| "barangay index is out of bounds".to_owned())?;
                Ok(PsgcEntry {
                    level,
                    code: self.string(row.code)?.to_owned(),
                    name: self.string(row.name)?.to_owned(),
                    region_name: None,
                    old_name: Some(self.string(row.old_name)?.to_owned()),
                    is_capital: false,
                    is_city: false,
                    is_municipality: false,
                    sub_municipality_code: self.optional_string(row.sub_municipality_code)?,
                    city_code: self.optional_string(row.city_code)?,
                    municipality_code: self.optional_string(row.municipality_code)?,
                    district_code: self.optional_string(row.district_code)?,
                    province_code: self.optional_string(row.province_code)?,
                    region_code: Some(self.string(row.region_code)?.to_owned()),
                    island_group_code: self.string(row.island_group_code)?.to_owned(),
                    psgc10_digit_code: self.string(row.psgc10_digit_code)?.to_owned(),
                })
            }
        }
    }

    fn string(&self, id: u32) -> Result<&str, String> {
        self.strings
            .get(id as usize)
            .map(String::as_str)
            .ok_or_else(|| "PSGC string id is out of bounds".to_owned())
    }

    fn optional_string(&self, id: u32) -> Result<Option<String>, String> {
        if id == MISSING_STRING {
            return Ok(None);
        }
        self.string(id).map(|value| Some(value.to_owned()))
    }

    fn numeric_id(&self, id: u32, label: &str) -> Result<u32, String> {
        self.string(id)?
            .parse::<u32>()
            .map_err(|_| format!("{label} is not numeric"))
    }

    fn optional_numeric_id(&self, id: u32, label: &str) -> Result<Option<u32>, String> {
        if id == MISSING_STRING {
            return Ok(None);
        }
        self.numeric_id(id, label).map(Some)
    }
}

static PSGC_INDEX: OnceLock<RwLock<Option<PsgcIndex>>> = OnceLock::new();

fn index_state() -> &'static RwLock<Option<PsgcIndex>> {
    PSGC_INDEX.get_or_init(|| RwLock::new(None))
}

/// Parses and owns a standalone compact PSGC artifact.
///
/// The artifact bytes are supplied by Flutter at runtime. No PSGC dataset is
/// linked into the Android ABI library.
pub fn initialize_psgc_index(artifact: Vec<u8>) -> PsgcInitializationResult {
    let index = match PsgcIndex::parse(&artifact) {
        Ok(index) => index,
        Err(message) => {
            return PsgcInitializationResult::error(PsgcOperationStatus::InvalidArtifact, message);
        }
    };
    let counts = match index.counts() {
        Ok(counts) => counts,
        Err(message) => {
            return PsgcInitializationResult::error(PsgcOperationStatus::InvalidArtifact, message);
        }
    };
    let result = match PsgcInitializationResult::ok(&index, counts) {
        Ok(result) => result,
        Err(message) => {
            return PsgcInitializationResult::error(PsgcOperationStatus::InvalidArtifact, message);
        }
    };
    match index_state().write() {
        Ok(mut guard) => {
            *guard = Some(index);
            result
        }
        Err(_) => PsgcInitializationResult::error(
            PsgcOperationStatus::InternalError,
            "PSGC index lock is unavailable",
        ),
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn query_psgc_index(level: PsgcLevel, parent_code: Option<String>) -> PsgcQueryResult {
    let guard = match index_state().read() {
        Ok(guard) => guard,
        Err(_) => {
            return PsgcQueryResult::error(
                PsgcOperationStatus::InternalError,
                "PSGC index lock is unavailable",
            );
        }
    };
    let Some(index) = guard.as_ref() else {
        return PsgcQueryResult::error(
            PsgcOperationStatus::NotInitialized,
            "PSGC index is not initialized",
        );
    };
    match index.query(level, parent_code.as_deref()) {
        Ok(entries) => PsgcQueryResult::ok(entries),
        Err(message) => PsgcQueryResult::error(PsgcOperationStatus::InternalError, message),
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn find_psgc_by_name(
    level: PsgcLevel,
    parent_code: Option<String>,
    name: String,
) -> PsgcLookupResult {
    let guard = match index_state().read() {
        Ok(guard) => guard,
        Err(_) => {
            return PsgcLookupResult::error(
                PsgcOperationStatus::InternalError,
                "PSGC index lock is unavailable",
            );
        }
    };
    let Some(index) = guard.as_ref() else {
        return PsgcLookupResult::error(
            PsgcOperationStatus::NotInitialized,
            "PSGC index is not initialized",
        );
    };
    match index.find_by_name(level, parent_code.as_deref(), &name) {
        Ok(entry) => PsgcLookupResult::ok(entry),
        Err(message) => PsgcLookupResult::error(PsgcOperationStatus::InternalError, message),
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn psgc_name_for_code(level: PsgcLevel, code: String) -> PsgcNameResult {
    let guard = match index_state().read() {
        Ok(guard) => guard,
        Err(_) => {
            return PsgcNameResult::error(
                PsgcOperationStatus::InternalError,
                "PSGC index lock is unavailable",
            );
        }
    };
    let Some(index) = guard.as_ref() else {
        return PsgcNameResult::error(
            PsgcOperationStatus::NotInitialized,
            "PSGC index is not initialized",
        );
    };
    match index.name_for_code(level, &code) {
        Ok(name) => PsgcNameResult::ok(name),
        Err(message) => PsgcNameResult::error(PsgcOperationStatus::InternalError, message),
    }
}

fn validate_counts(
    regions: usize,
    provinces: usize,
    cities: usize,
    barangays: usize,
    strings: usize,
) -> Result<(), String> {
    if regions > 100
        || provinces > 500
        || cities > 10_000
        || barangays > 100_000
        || strings > MAX_STRINGS
    {
        return Err("PSGC artifact counts exceed safety limits".to_owned());
    }
    Ok(())
}

fn read_required_id(reader: &mut Cursor<'_>, string_count: usize) -> Result<u32, String> {
    let id = reader.read_u32()?;
    if id == MISSING_STRING || id as usize >= string_count {
        return Err("PSGC required string id is invalid".to_owned());
    }
    Ok(id)
}

fn read_optional_id(reader: &mut Cursor<'_>, string_count: usize) -> Result<u32, String> {
    let id = reader.read_u32()?;
    if id != MISSING_STRING && id as usize >= string_count {
        return Err("PSGC optional string id is invalid".to_owned());
    }
    Ok(id)
}

fn parse_code(value: &str) -> Option<u32> {
    if value.len() != 9 || !value.bytes().all(|byte| byte.is_ascii_digit()) {
        return None;
    }
    value.parse::<u32>().ok()
}

fn normalize_name(level: PsgcLevel, value: &str) -> String {
    let lowered = value.to_lowercase();
    if level == PsgcLevel::Barangay {
        lowered
            .replace("barangay", "")
            .replace("brgy.", "")
            .trim()
            .to_owned()
    } else {
        lowered.replace("city of", "").trim().to_owned()
    }
}

fn fnv1a(bytes: &[u8]) -> u64 {
    bytes.iter().fold(FNV_OFFSET_BASIS, |hash, byte| {
        (hash ^ u64::from(*byte)).wrapping_mul(FNV_PRIME)
    })
}

struct Cursor<'a> {
    bytes: &'a [u8],
    offset: usize,
}

impl<'a> Cursor<'a> {
    fn new(bytes: &'a [u8], offset: usize) -> Self {
        Self { bytes, offset }
    }

    fn is_at_end(&self) -> bool {
        self.offset == self.bytes.len()
    }

    fn read_u8(&mut self) -> Result<u8, String> {
        let value = self
            .bytes
            .get(self.offset)
            .copied()
            .ok_or_else(|| "PSGC artifact is truncated".to_owned())?;
        self.offset += 1;
        Ok(value)
    }

    fn read_u32(&mut self) -> Result<u32, String> {
        let bytes = self.read_array::<4>()?;
        Ok(u32::from_le_bytes(bytes))
    }

    fn read_u64(&mut self) -> Result<u64, String> {
        let bytes = self.read_array::<8>()?;
        Ok(u64::from_le_bytes(bytes))
    }

    fn read_string(&mut self) -> Result<String, String> {
        let length = self.read_u32()? as usize;
        let end = self
            .offset
            .checked_add(length)
            .ok_or_else(|| "PSGC string length overflowed".to_owned())?;
        let bytes = self
            .bytes
            .get(self.offset..end)
            .ok_or_else(|| "PSGC artifact is truncated".to_owned())?;
        self.offset = end;
        std::str::from_utf8(bytes)
            .map(str::to_owned)
            .map_err(|_| "PSGC artifact contains invalid UTF-8".to_owned())
    }

    fn read_array<const LENGTH: usize>(&mut self) -> Result<[u8; LENGTH], String> {
        let end = self
            .offset
            .checked_add(LENGTH)
            .ok_or_else(|| "PSGC artifact offset overflowed".to_owned())?;
        let slice = self
            .bytes
            .get(self.offset..end)
            .ok_or_else(|| "PSGC artifact is truncated".to_owned())?;
        let array =
            <[u8; LENGTH]>::try_from(slice).map_err(|_| "PSGC artifact is truncated".to_owned())?;
        self.offset = end;
        Ok(array)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn compact_artifact_supports_ordered_queries_and_lookups() {
        let artifact = include_bytes!("../../../assets/regionJson/psgc_index_v1.bin");
        let initialized = initialize_psgc_index(artifact.to_vec());
        assert_eq!(initialized.status, PsgcOperationStatus::Ok);
        assert_eq!(initialized.counts.regions, 17);
        assert_eq!(initialized.counts.provinces, 81);
        assert_eq!(initialized.counts.cities, 1_634);
        assert_eq!(initialized.counts.barangays, 42_046);
        assert_eq!(initialized.format_version, 1);
        assert_eq!(initialized.artifact_bytes, 3_474_156);
        assert_eq!(initialized.payload_bytes, 3_474_112);
        assert_eq!(initialized.payload_checksum_hex, "57417d883f20e124");
        assert_eq!(initialized.string_count, 115_909);

        let regions = query_psgc_index(PsgcLevel::Region, None);
        assert_eq!(regions.status, PsgcOperationStatus::Ok);
        assert_eq!(
            regions.entries.first().map(|entry| entry.code.as_str()),
            Some("010000000")
        );
        assert_eq!(
            regions.entries.last().map(|entry| entry.code.as_str()),
            Some("150000000")
        );

        let cities = query_psgc_index(PsgcLevel::City, Some("012800000".to_owned()));
        assert_eq!(cities.status, PsgcOperationStatus::Ok);
        assert_eq!(
            cities.entries.first().map(|entry| entry.name.as_str()),
            Some("Adams")
        );

        let barangays = query_psgc_index(PsgcLevel::Barangay, Some("012801000".to_owned()));
        assert_eq!(barangays.status, PsgcOperationStatus::Ok);
        assert_eq!(
            barangays.entries.first().map(|entry| entry.name.as_str()),
            Some("Adams (Pob.)")
        );
        assert!(barangays
            .entries
            .iter()
            .all(|entry| entry.municipality_code.as_deref() == Some("012801000")));

        let fuzzy = find_psgc_by_name(
            PsgcLevel::Barangay,
            Some("012801000".to_owned()),
            "Barangay Adams (Pob.)".to_owned(),
        );
        assert_eq!(fuzzy.status, PsgcOperationStatus::Ok);
        assert_eq!(
            fuzzy.entry.as_ref().map(|entry| entry.code.as_str()),
            Some("012801001")
        );

        let name = psgc_name_for_code(PsgcLevel::Province, "012800000".to_owned());
        assert_eq!(name.status, PsgcOperationStatus::Ok);
        assert_eq!(name.name.as_deref(), Some("Ilocos Norte"));
        let non_canonical_code = psgc_name_for_code(PsgcLevel::Province, "12800000".to_owned());
        assert_eq!(non_canonical_code.status, PsgcOperationStatus::Ok);
        assert_eq!(non_canonical_code.name, None);

        let mut corrupted = artifact.to_vec();
        if let Some(last) = corrupted.last_mut() {
            *last ^= 1;
        }
        let rejected = initialize_psgc_index(corrupted);
        assert_eq!(rejected.status, PsgcOperationStatus::InvalidArtifact);
    }
}
