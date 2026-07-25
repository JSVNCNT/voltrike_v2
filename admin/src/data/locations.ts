export interface Region { code: string; name: string; }
export interface City { code: string; name: string; regionCode: string; }
export interface Barangay { code: string; name: string; regionCode: string; cityCode?: string; municipalityCode?: string; }

const load = async <T>(file: string): Promise<T[]> => {
  const response = await fetch(`/regionJson/${file}`);
  if (!response.ok) throw new Error('The official location list could not be loaded.');
  return response.json() as Promise<T[]>;
};

// This deliberately loads source data only on the TODA registration page.
export async function loadPhilippineLocations() {
  const [regions, cities, barangays] = await Promise.all([
    load<Region>('regions.json'),
    load<City>('cities-municipalities.json'),
    load<Barangay>('barangays.json'),
  ]);
  return { regions, cities, barangays };
}
