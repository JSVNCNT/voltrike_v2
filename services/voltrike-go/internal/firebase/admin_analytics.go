package firebase

import (
	"context"
	"time"

	"cloud.google.com/go/firestore"
)

const (
	overviewAnalyticsDays     = 14
	overviewAnalyticsMaxItems = 5000
)

type overviewAnalyticsDay struct {
	date              string
	bookings          int
	completedRides    int
	grossFare         float64
	commissionAmount  float64
	driverNetEarnings float64
}

// adminOverviewAnalytics returns a small, presentation-safe set of daily
// buckets. Firestore remains authoritative; the browser never downloads the
// booking or settlement documents used to produce the charts.
func (store *Store) adminOverviewAnalytics(ctx context.Context, actor adminIdentity) (map[string]any, error) {
	location, err := time.LoadLocation("Asia/Manila")
	if err != nil {
		return nil, err
	}
	now := time.Now().In(location)
	end := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, location).AddDate(0, 0, 1)
	start := end.AddDate(0, 0, -overviewAnalyticsDays)

	bookingSnapshots, err := store.firestore.Collection("bookings").
		Where("createdAt", ">=", start.UTC()).
		OrderBy("createdAt", firestore.Desc).
		Limit(overviewAnalyticsMaxItems + 1).
		Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	settlementSnapshots, err := store.firestore.Collection("settlements").
		Where("settlementTimestamp", ">=", start.UTC()).
		OrderBy("settlementTimestamp", firestore.Desc).
		Limit(overviewAnalyticsMaxItems + 1).
		Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}

	truncated := len(bookingSnapshots) > overviewAnalyticsMaxItems || len(settlementSnapshots) > overviewAnalyticsMaxItems
	if len(bookingSnapshots) > overviewAnalyticsMaxItems {
		bookingSnapshots = bookingSnapshots[:overviewAnalyticsMaxItems]
	}
	if len(settlementSnapshots) > overviewAnalyticsMaxItems {
		settlementSnapshots = settlementSnapshots[:overviewAnalyticsMaxItems]
	}
	bookings := make([]map[string]any, 0, len(bookingSnapshots))
	for _, snapshot := range bookingSnapshots {
		bookings = append(bookings, snapshot.Data())
	}
	settlements := make([]map[string]any, 0, len(settlementSnapshots))
	for _, snapshot := range settlementSnapshots {
		settlements = append(settlements, snapshot.Data())
	}

	result := buildOverviewAnalytics(actor, bookings, settlements, start, end, location)
	result["generatedAt"] = time.Now().UTC()
	result["truncated"] = truncated
	return result, nil
}

func buildOverviewAnalytics(
	actor adminIdentity,
	bookings []map[string]any,
	settlements []map[string]any,
	start time.Time,
	end time.Time,
	location *time.Location,
) map[string]any {
	days := make([]overviewAnalyticsDay, overviewAnalyticsDays)
	dayIndex := make(map[string]int, overviewAnalyticsDays)
	for index := range days {
		date := start.AddDate(0, 0, index).In(location).Format("2006-01-02")
		days[index].date = date
		dayIndex[date] = index
	}

	for _, booking := range bookings {
		if !actor.canAccessToda(text(booking, "todaId", "driverTodaId", "ownerTodaId")) {
			continue
		}
		createdAt := analyticsTimestamp(booking, "createdAt", "requestedAt")
		if createdAt.Before(start) || !createdAt.Before(end) {
			continue
		}
		if index, ok := dayIndex[createdAt.In(location).Format("2006-01-02")]; ok {
			days[index].bookings++
		}
	}

	for _, settlement := range settlements {
		if !actor.canAccessToda(text(settlement, "todaId", "driverTodaId", "ownerTodaId")) {
			continue
		}
		occurredAt := analyticsTimestamp(settlement, "settlementTimestamp", "completedAt", "createdAt")
		if occurredAt.Before(start) || !occurredAt.Before(end) || text(settlement, "status", "settlementStatus") != "settled" {
			continue
		}
		index, ok := dayIndex[occurredAt.In(location).Format("2006-01-02")]
		if !ok {
			continue
		}
		days[index].completedRides++
		days[index].grossFare += number(settlement, "grossFare", "amountDue")
		days[index].commissionAmount += number(settlement, "commissionAmount")
		days[index].driverNetEarnings += number(settlement, "driverNetEarnings")
	}

	items := make([]map[string]any, 0, len(days))
	for _, day := range days {
		items = append(items, map[string]any{
			"date":              day.date,
			"bookings":          day.bookings,
			"completedRides":    day.completedRides,
			"grossFare":         mathRound(day.grossFare, 2),
			"commissionAmount":  mathRound(day.commissionAmount, 2),
			"driverNetEarnings": mathRound(day.driverNetEarnings, 2),
		})
	}
	scope := "platform"
	if !actor.developer() {
		scope = actor.TodaID
	}
	return map[string]any{
		"startDate": start.In(location).Format("2006-01-02"),
		"endDate":   end.Add(-time.Nanosecond).In(location).Format("2006-01-02"),
		"timeZone":  location.String(),
		"scope":     scope,
		"days":      items,
	}
}

func analyticsTimestamp(data map[string]any, keys ...string) time.Time {
	for _, key := range keys {
		switch value := data[key].(type) {
		case time.Time:
			return value
		case *time.Time:
			if value != nil {
				return *value
			}
		}
	}
	return time.Time{}
}
