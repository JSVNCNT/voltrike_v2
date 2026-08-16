package core

import (
	"errors"
	"fmt"
	"math"
	"sort"
	"strings"
)

const (
	MaxAreas       = 20
	MaxPoints      = 200
	MaxRoutePoints = 10000
)

type Coordinate struct {
	Latitude  float64 `json:"latitude"`
	Longitude float64 `json:"longitude"`
}

func (point Coordinate) Valid() bool {
	return !math.IsNaN(point.Latitude) && !math.IsInf(point.Latitude, 0) &&
		!math.IsNaN(point.Longitude) && !math.IsInf(point.Longitude, 0) &&
		point.Latitude >= -90 && point.Latitude <= 90 && point.Longitude >= -180 && point.Longitude <= 180
}

func RequireCoordinate(point Coordinate, name string) (Coordinate, error) {
	if !point.Valid() {
		return Coordinate{}, fmt.Errorf("%s coordinates are invalid", name)
	}
	return point, nil
}

type Area struct {
	Points []Coordinate `json:"points"`
}

type Geofence struct {
	ID               string `json:"id"`
	TodaID           string `json:"todaId"`
	IsActive         bool   `json:"isActive"`
	CoverageRevision int    `json:"coverageRevision"`
	Areas            []Area `json:"areas"`
}

type Restriction struct {
	ID                         string  `json:"id"`
	Name                       string  `json:"name"`
	Type                       string  `json:"type"`
	IsActive                   bool    `json:"isActive"`
	GeometryType               string  `json:"geometryType"`
	BufferMeters               float64 `json:"bufferMeters"`
	MinimumAlignedTravelMeters float64 `json:"minimumAlignedTravelMeters"`
	Areas                      []Area  `json:"areas"`
}

type FareConfig struct {
	Version                int     `json:"version"`
	BaseFare               float64 `json:"baseFare"`
	IncludedMeters         int     `json:"includedMeters"`
	DistanceStepMeters     int     `json:"distanceStepMeters"`
	DistanceStepPrice      float64 `json:"distanceStepPrice"`
	AdditionalPassengerFee float64 `json:"additionalPassengerFee"`
	BaggageFee             float64 `json:"baggageFee"`
	OutsideTodaSurcharge   float64 `json:"outsideTodaSurcharge"`
	AdditionalDropoffFee   float64 `json:"additionalDropoffFee"`
	Currency               string  `json:"currency"`
}

var DefaultFare = FareConfig{
	Version: 1, BaseFare: 20, IncludedMeters: 1000, DistanceStepMeters: 500,
	DistanceStepPrice: 5, AdditionalPassengerFee: 40, BaggageFee: 20,
	OutsideTodaSurcharge: 20, AdditionalDropoffFee: 10, Currency: "PHP",
}

type FareBreakdown struct {
	BaseFare                float64 `json:"baseFare"`
	IncludedMeters          int     `json:"includedMeters"`
	ChargeableMeters        int     `json:"chargeableMeters"`
	DistanceSteps           int     `json:"distanceSteps"`
	DistanceStepMeters      int     `json:"distanceStepMeters"`
	DistanceStepPrice       float64 `json:"distanceStepPrice"`
	DistanceFare            float64 `json:"distanceFare"`
	AdditionalPassengers    int     `json:"additionalPassengers"`
	AdditionalPassengerFare float64 `json:"additionalPassengerFare"`
	BaggageCount            int     `json:"baggageCount"`
	BaggageFare             float64 `json:"baggageFare"`
	IsOutsideToda           bool    `json:"isOutsideToda"`
	BoundarySurcharge       float64 `json:"boundarySurcharge"`
	DropoffCount            int     `json:"dropoffCount"`
	AdditionalDropoffs      int     `json:"additionalDropoffs"`
	AdditionalDropoffFare   float64 `json:"additionalDropoffFare"`
	Currency                string  `json:"currency"`
	Total                   float64 `json:"total"`
}

func SnapshotFare(raw FareConfig) FareConfig {
	if raw == (FareConfig{}) {
		return DefaultFare
	}
	result := DefaultFare
	if raw.Version > 0 {
		result.Version = raw.Version
	}
	if raw.BaseFare >= 0 {
		result.BaseFare = currency(raw.BaseFare)
	}
	if raw.IncludedMeters > 0 {
		result.IncludedMeters = raw.IncludedMeters
	}
	if raw.DistanceStepMeters > 0 {
		result.DistanceStepMeters = raw.DistanceStepMeters
	}
	if raw.DistanceStepPrice >= 0 {
		result.DistanceStepPrice = currency(raw.DistanceStepPrice)
	}
	if raw.AdditionalPassengerFee >= 0 {
		result.AdditionalPassengerFee = currency(raw.AdditionalPassengerFee)
	}
	if raw.BaggageFee >= 0 {
		result.BaggageFee = currency(raw.BaggageFee)
	}
	if raw.OutsideTodaSurcharge >= 0 {
		result.OutsideTodaSurcharge = currency(raw.OutsideTodaSurcharge)
	}
	if raw.AdditionalDropoffFee >= 0 {
		result.AdditionalDropoffFee = currency(raw.AdditionalDropoffFee)
	}
	if raw.Currency == "PHP" {
		result.Currency = raw.Currency
	}
	return result
}

func CalculateFare(raw FareConfig, distanceMeters, additionalPassengers, baggageCount int, outside bool) FareBreakdown {
	return CalculateFareForDropoffs(raw, distanceMeters, additionalPassengers, baggageCount, 1, outside)
}

func CalculateFareForDropoffs(raw FareConfig, distanceMeters, additionalPassengers, baggageCount, dropoffCount int, outside bool) FareBreakdown {
	cfg := SnapshotFare(raw)
	if distanceMeters < 0 {
		distanceMeters = 0
	}
	if additionalPassengers < 0 {
		additionalPassengers = 0
	}
	if baggageCount < 0 {
		baggageCount = 0
	}
	if dropoffCount < 1 {
		dropoffCount = 1
	}
	additionalDropoffs := max(0, dropoffCount-1)
	chargeable := max(0, distanceMeters-cfg.IncludedMeters)
	steps := int(math.Ceil(float64(chargeable) / float64(cfg.DistanceStepMeters)))
	distanceFareCents := steps * cents(cfg.DistanceStepPrice)
	passengerCents := additionalPassengers * cents(cfg.AdditionalPassengerFee)
	baggageCents := baggageCount * cents(cfg.BaggageFee)
	boundaryCents := 0
	if outside {
		boundaryCents = cents(cfg.OutsideTodaSurcharge)
	}
	additionalDropoffCents := additionalDropoffs * cents(cfg.AdditionalDropoffFee)
	totalCents := cents(cfg.BaseFare) + distanceFareCents + passengerCents + baggageCents + boundaryCents + additionalDropoffCents
	return FareBreakdown{
		BaseFare: cfg.BaseFare, IncludedMeters: cfg.IncludedMeters, ChargeableMeters: chargeable,
		DistanceSteps: steps, DistanceStepMeters: cfg.DistanceStepMeters, DistanceStepPrice: cfg.DistanceStepPrice,
		DistanceFare: pesos(distanceFareCents), AdditionalPassengers: additionalPassengers,
		AdditionalPassengerFare: pesos(passengerCents), BaggageCount: baggageCount,
		BaggageFare: pesos(baggageCents), IsOutsideToda: outside,
		BoundarySurcharge: pesos(boundaryCents), DropoffCount: dropoffCount,
		AdditionalDropoffs: additionalDropoffs, AdditionalDropoffFare: pesos(additionalDropoffCents),
		Currency: cfg.Currency, Total: pesos(totalCents),
	}
}

func cents(amount float64) int       { return int(math.Round(amount * 100)) }
func pesos(value int) float64        { return float64(value) / 100 }
func currency(value float64) float64 { return pesos(cents(value)) }
func max(left, right int) int {
	if left > right {
		return left
	}
	return right
}

type Coverage struct {
	Configured         bool           `json:"configured"`
	Serviceable        bool           `json:"serviceable"`
	IsOutsideToda      bool           `json:"isOutsideToda"`
	CoverageClass      string         `json:"coverageClass"`
	PickupTodaIDs      []string       `json:"pickupTodaIds"`
	DestinationTodaIDs []string       `json:"destinationTodaIds"`
	SharedTodaIDs      []string       `json:"sharedTodaIds"`
	PrimaryTodaIDs     []string       `json:"primaryTodaIds"`
	SecondaryTodaIDs   []string       `json:"secondaryTodaIds"`
	AllowAnyActiveToda bool           `json:"allowAnyActiveToda"`
	EligibleTodaIDs    []string       `json:"eligibleTodaIds"`
	ServiceTodaID      *string        `json:"serviceTodaId"`
	GeofenceRevisions  map[string]int `json:"geofenceRevisions"`
}

func ClassifyCoverage(geofences []Geofence, pickup, destination Coordinate) (Coverage, error) {
	return ClassifyCoverageStops(geofences, pickup, []Coordinate{destination})
}

func ClassifyCoverageStops(geofences []Geofence, pickup Coordinate, destinations []Coordinate) (Coverage, error) {
	if _, err := RequireCoordinate(pickup, "Pickup"); err != nil {
		return Coverage{}, err
	}
	if len(destinations) == 0 {
		return Coverage{}, fmt.Errorf("at least one destination is required")
	}
	for index, destination := range destinations {
		if _, err := RequireCoordinate(destination, fmt.Sprintf("Destination %d", index+1)); err != nil {
			return Coverage{}, err
		}
	}
	valid := make([]Geofence, 0, len(geofences))
	for _, item := range geofences {
		if !item.IsActive || item.TodaID == "" || !validAreas(item.Areas, 3) {
			continue
		}
		valid = append(valid, item)
	}
	matching := func(point Coordinate) []string {
		matches := map[string]struct{}{}
		for _, geofence := range valid {
			if containsAny(geofence.Areas, point) {
				matches[geofence.TodaID] = struct{}{}
			}
		}
		return sortedKeys(matches)
	}
	pickupIDs := matching(pickup)
	destinationUnion := map[string]struct{}{}
	sharedSet := toSet(pickupIDs)
	allDestinationsCovered := true
	for _, destination := range destinations {
		ids := matching(destination)
		if len(ids) == 0 {
			allDestinationsCovered = false
		}
		current := toSet(ids)
		for id := range current {
			destinationUnion[id] = struct{}{}
		}
		for id := range sharedSet {
			if _, ok := current[id]; !ok {
				delete(sharedSet, id)
			}
		}
	}
	destinationIDs := sortedKeys(destinationUnion)
	shared := sortedKeys(sharedSet)
	primary := shared
	if len(primary) == 0 {
		primary = pickupIDs
	}
	if len(primary) == 0 {
		primary = destinationIDs
	}
	primarySet := toSet(primary)
	all := toSet(append(append([]string{}, pickupIDs...), destinationIDs...))
	secondary := make([]string, 0)
	for _, id := range sortedKeys(all) {
		if _, ok := primarySet[id]; !ok {
			secondary = append(secondary, id)
		}
	}
	revisions := map[string]int{}
	for _, geofence := range valid {
		if _, ok := all[geofence.TodaID]; ok && geofence.CoverageRevision > revisions[geofence.TodaID] {
			revisions[geofence.TodaID] = geofence.CoverageRevision
		}
	}
	coverageClass := "unconfigured_fallback"
	if len(valid) > 0 {
		switch {
		case len(shared) > 0:
			coverageClass = "intra_toda"
		case len(pickupIDs) > 0 && allDestinationsCovered:
			coverageClass = "cross_boundary"
		case len(pickupIDs) > 0:
			coverageClass = "destination_outside_coverage"
		case len(destinationIDs) > 0:
			coverageClass = "pickup_outside_coverage"
		default:
			coverageClass = "outside_network"
		}
	}
	eligible := append(append([]string{}, primary...), secondary...)
	var serviceID *string
	if len(primary) == 1 {
		serviceID = &primary[0]
	}
	return Coverage{Configured: len(valid) > 0, Serviceable: true, IsOutsideToda: len(valid) > 0 && len(shared) == 0,
		CoverageClass: coverageClass, PickupTodaIDs: pickupIDs, DestinationTodaIDs: destinationIDs,
		SharedTodaIDs: shared, PrimaryTodaIDs: primary, SecondaryTodaIDs: secondary,
		AllowAnyActiveToda: true, EligibleTodaIDs: eligible, ServiceTodaID: serviceID,
		GeofenceRevisions: revisions}, nil
}

func FirstEndpointConflict(pickup, destination Coordinate, restrictions []Restriction) *Restriction {
	return FirstEndpointConflictStops(append([]Coordinate{pickup}, destination), restrictions)
}

func FirstEndpointConflictStops(points []Coordinate, restrictions []Restriction) *Restriction {
	for index := range restrictions {
		item := &restrictions[index]
		if !endpointBlocking(*item) {
			continue
		}
		for _, point := range points {
			if containsAny(item.Areas, point) {
				return item
			}
		}
	}
	return nil
}

func FirstRouteConflict(route []Coordinate, restrictions []Restriction) *Restriction {
	for index := range restrictions {
		item := &restrictions[index]
		if endpointBlocking(*item) && item.GeometryType != "corridor" && routeConflicts(route, *item) {
			return item
		}
	}
	return nil
}

func FirstHighwayConflict(route []Coordinate, restrictions []Restriction) *Restriction {
	for index := range restrictions {
		item := &restrictions[index]
		if item.IsActive && item.Type == "prohibited_highway" && item.GeometryType == "corridor" {
			threshold := item.MinimumAlignedTravelMeters
			if threshold < 30 {
				threshold = 80
			}
			if highwayTravel(route, *item) >= threshold {
				return item
			}
		}
	}
	return nil
}

func DecodePolyline(encoded string) ([]Coordinate, error) {
	if len(encoded) == 0 || len(encoded) > 100000 {
		return nil, errors.New("encoded route polyline is invalid")
	}
	points := make([]Coordinate, 0, 128)
	var latitude, longitude int
	index := 0
	decode := func() (int, error) {
		var result, shift int
		for {
			if index >= len(encoded) || shift > 30 {
				return 0, errors.New("encoded route polyline is invalid")
			}
			byteValue := int(encoded[index]) - 63
			index++
			if byteValue < 0 || byteValue > 63 {
				return 0, errors.New("encoded route polyline is invalid")
			}
			result |= (byteValue & 0x1f) << shift
			shift += 5
			if byteValue < 0x20 {
				break
			}
		}
		if result&1 != 0 {
			return ^(result >> 1), nil
		}
		return result >> 1, nil
	}
	for index < len(encoded) {
		latDelta, err := decode()
		if err != nil {
			return nil, err
		}
		lngDelta, err := decode()
		if err != nil {
			return nil, err
		}
		latitude += latDelta
		longitude += lngDelta
		point := Coordinate{Latitude: float64(latitude) / 1e5, Longitude: float64(longitude) / 1e5}
		if !point.Valid() {
			return nil, errors.New("encoded route polyline is invalid")
		}
		points = append(points, point)
		if len(points) > MaxRoutePoints {
			return nil, errors.New("encoded route polyline exceeds point limit")
		}
	}
	return points, nil
}

func EncodePolyline(points []Coordinate) (string, error) {
	if len(points) < 2 || len(points) > MaxRoutePoints {
		return "", errors.New("route polyline point count is invalid")
	}
	var builder strings.Builder
	previousLatitude, previousLongitude := 0, 0
	encode := func(delta int) {
		value := delta << 1
		if delta < 0 {
			value = ^value
		}
		for value >= 0x20 {
			builder.WriteByte(byte((0x20 | (value & 0x1f)) + 63))
			value >>= 5
		}
		builder.WriteByte(byte(value + 63))
	}
	for _, point := range points {
		if !point.Valid() {
			return "", errors.New("route polyline contains an invalid point")
		}
		latitude := int(math.Round(point.Latitude * 1e5))
		longitude := int(math.Round(point.Longitude * 1e5))
		encode(latitude - previousLatitude)
		encode(longitude - previousLongitude)
		previousLatitude, previousLongitude = latitude, longitude
	}
	return builder.String(), nil
}

func HaversineMeters(left, right Coordinate) float64 {
	const radius = 6371000.0
	lat := radians(right.Latitude - left.Latitude)
	lng := radians(right.Longitude - left.Longitude)
	a := math.Sin(lat/2)*math.Sin(lat/2) + math.Cos(radians(left.Latitude))*math.Cos(radians(right.Latitude))*math.Sin(lng/2)*math.Sin(lng/2)
	return radius * 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
}

func validAreas(areas []Area, minimum int) bool {
	if len(areas) == 0 || len(areas) > MaxAreas {
		return false
	}
	for _, area := range areas {
		if len(area.Points) < minimum || len(area.Points) > MaxPoints {
			return false
		}
		for _, point := range area.Points {
			if !point.Valid() {
				return false
			}
		}
	}
	return true
}

func endpointBlocking(item Restriction) bool {
	return item.IsActive && item.GeometryType != "corridor" &&
		(item.Type == "no_service_area" || item.Type == "restricted_crossing" || item.Type == "restricted_driving_area") &&
		validAreas(item.Areas, 3)
}

func containsAny(areas []Area, point Coordinate) bool {
	for _, area := range areas {
		if pointInPolygon(point, area.Points) {
			return true
		}
	}
	return false
}

func pointInPolygon(point Coordinate, polygon []Coordinate) bool {
	if len(polygon) < 3 {
		return false
	}
	inside := false
	previous := len(polygon) - 1
	for current := range polygon {
		start, end := polygon[previous], polygon[current]
		if pointOnSegment(point, start, end) {
			return true
		}
		crosses := (end.Latitude > point.Latitude) != (start.Latitude > point.Latitude) &&
			point.Longitude < (start.Longitude-end.Longitude)*(point.Latitude-end.Latitude)/(start.Latitude-end.Latitude)+end.Longitude
		if crosses {
			inside = !inside
		}
		previous = current
	}
	return inside
}

func routeConflicts(route []Coordinate, item Restriction) bool {
	if len(route) < 2 || !validAreas(item.Areas, 3) {
		return false
	}
	for _, area := range item.Areas {
		for _, point := range route {
			if pointInPolygon(point, area.Points) {
				return true
			}
		}
		for index := 1; index < len(route); index++ {
			for polygonIndex := range area.Points {
				if segmentsIntersect(route[index-1], route[index], area.Points[polygonIndex], area.Points[(polygonIndex+1)%len(area.Points)]) {
					return true
				}
			}
		}
	}
	return false
}

func highwayTravel(route []Coordinate, item Restriction) float64 {
	if len(route) < 2 || !validAreas(item.Areas, 2) || item.BufferMeters <= 0 {
		return 0
	}
	var aligned float64
	for index := 1; index < len(route); index++ {
		start, end := route[index-1], route[index]
		segment := HaversineMeters(start, end)
		if segment < 1 {
			continue
		}
		samples := int(math.Max(1, math.Ceil(segment/12)))
		for sample := 0; sample < samples; sample++ {
			fraction := (float64(sample) + 0.5) / float64(samples)
			midpoint := Coordinate{Latitude: start.Latitude + (end.Latitude-start.Latitude)*fraction, Longitude: start.Longitude + (end.Longitude-start.Longitude)*fraction}
			closestStart, closestEnd, closestDistance, found := closestSegment(midpoint, item.Areas)
			if found && closestDistance <= item.BufferMeters && headingDifference(start, end, closestStart, closestEnd) <= 45 {
				aligned += segment / float64(samples)
			}
		}
	}
	return aligned
}

func closestSegment(point Coordinate, areas []Area) (Coordinate, Coordinate, float64, bool) {
	best := math.Inf(1)
	var bestStart, bestEnd Coordinate
	found := false
	for _, area := range areas {
		for index := 1; index < len(area.Points); index++ {
			distance := pointToSegmentMeters(point, area.Points[index-1], area.Points[index])
			if distance < best {
				best, bestStart, bestEnd, found = distance, area.Points[index-1], area.Points[index], true
			}
		}
	}
	return bestStart, bestEnd, best, found
}

func pointToSegmentMeters(point, start, end Coordinate) float64 {
	const metresPerDegree = 111320.0
	reference := radians((point.Latitude + start.Latitude + end.Latitude) / 3)
	longitudeScale := metresPerDegree * math.Cos(reference)
	px, py := (point.Longitude-start.Longitude)*longitudeScale, (point.Latitude-start.Latitude)*metresPerDegree
	sx, sy := (end.Longitude-start.Longitude)*longitudeScale, (end.Latitude-start.Latitude)*metresPerDegree
	length := sx*sx + sy*sy
	if length == 0 {
		return math.Hypot(px, py)
	}
	projection := math.Max(0, math.Min(1, (px*sx+py*sy)/length))
	return math.Hypot(px-sx*projection, py-sy*projection)
}

func pointOnSegment(point, start, end Coordinate) bool {
	cross := (point.Longitude-start.Longitude)*(end.Latitude-start.Latitude) - (point.Latitude-start.Latitude)*(end.Longitude-start.Longitude)
	if math.Abs(cross) > 1e-9 {
		return false
	}
	dot := (point.Longitude-start.Longitude)*(end.Longitude-start.Longitude) + (point.Latitude-start.Latitude)*(end.Latitude-start.Latitude)
	if dot < 0 {
		return false
	}
	length := (end.Longitude-start.Longitude)*(end.Longitude-start.Longitude) + (end.Latitude-start.Latitude)*(end.Latitude-start.Latitude)
	return dot <= length
}

func segmentsIntersect(a, b, c, d Coordinate) bool {
	abc, abd, cda, cdb := orientation(a, b, c), orientation(a, b, d), orientation(c, d, a), orientation(c, d, b)
	if abc != abd && cda != cdb {
		return true
	}
	return (abc == 0 && pointOnSegment(c, a, b)) || (abd == 0 && pointOnSegment(d, a, b)) || (cda == 0 && pointOnSegment(a, c, d)) || (cdb == 0 && pointOnSegment(b, c, d))
}

func orientation(a, b, c Coordinate) int {
	value := (b.Longitude-a.Longitude)*(c.Latitude-a.Latitude) - (b.Latitude-a.Latitude)*(c.Longitude-a.Longitude)
	if math.Abs(value) <= 1e-12 {
		return 0
	}
	if value > 0 {
		return 1
	}
	return -1
}

func headingDifference(start, end, lineStart, lineEnd Coordinate) float64 {
	heading := func(a, b Coordinate) float64 {
		return math.Atan2(b.Latitude-a.Latitude, (b.Longitude-a.Longitude)*math.Cos(radians((a.Latitude+b.Latitude)/2))) * 180 / math.Pi
	}
	difference := math.Mod(math.Abs(heading(start, end)-heading(lineStart, lineEnd)), 180)
	if difference > 90 {
		return 180 - difference
	}
	return difference
}

func radians(value float64) float64 { return value * math.Pi / 180 }
func toSet(items []string) map[string]struct{} {
	result := map[string]struct{}{}
	for _, item := range items {
		result[item] = struct{}{}
	}
	return result
}
func sortedKeys(items map[string]struct{}) []string {
	result := make([]string, 0, len(items))
	for item := range items {
		result = append(result, item)
	}
	sort.Strings(result)
	return result
}
