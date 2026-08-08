package firebase

import (
	"context"
	"fmt"
	"path"
	"regexp"
	"sort"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"cloud.google.com/go/firestore"
	gcs "cloud.google.com/go/storage"
	"github.com/google/uuid"
	"github.com/voltrike/voltrike-go/internal/app"
)

type chatModerationRule struct {
	ID            string
	Phrase        string
	Language      string
	Category      string
	Severity      string
	Action        string
	MatchMode     string
	MatchVariants bool
	Aliases       []string
}

type chatModerationMatch struct {
	RuleID        string
	Phrase        string
	Language      string
	Category      string
	Severity      string
	Action        string
	MatchMode     string
	MatchVariants bool
}

type chatModerationResult struct {
	DisplayText string
	Matches     []chatModerationMatch
	Flagged     bool
	Blocked     bool
}

type chatModerationIncidentInput struct {
	Booking           map[string]any
	BookingID         string
	MessageID         string
	SenderID          string
	OriginalText      string
	DisplayText       string
	Matches           []chatModerationMatch
	MessageType       string
	MediaPath         string
	MediaEvidencePath string
	DeliveryStatus    string
}

// ModerateChatText applies the active server-managed ride-chat safety rules.
func (store *Store) ModerateChatText(ctx context.Context, original string) (chatModerationResult, error) {
	rules, err := store.activeChatModerationRules(ctx)
	if err != nil {
		return chatModerationResult{}, err
	}
	result := chatModerationResult{DisplayText: original}
	for _, rule := range rules {
		matched := false
		candidates := append([]string{rule.Phrase}, rule.Aliases...)
		for _, candidate := range candidates {
			next, candidateMatched := maskModeratedPhraseAdvanced(result.DisplayText, candidate, rule.MatchMode, rule.MatchVariants)
			if candidateMatched {
				result.DisplayText = next
				matched = true
			}
		}
		if !matched {
			continue
		}
		result.Matches = append(result.Matches, chatModerationMatch{
			RuleID: rule.ID, Phrase: rule.Phrase, Language: rule.Language,
			Category: rule.Category, Severity: rule.Severity, Action: rule.Action,
			MatchMode: rule.MatchMode, MatchVariants: rule.MatchVariants,
		})
		// Every configured match is retained as safety evidence. "mask" still
		// delivers the sanitized text; "flag" and "block" communicate a higher
		// severity policy decision.
		result.Flagged = true
		if rule.Action == "block" {
			result.Blocked = true
		}
	}
	return result, nil
}

func (store *Store) activeChatModerationRules(ctx context.Context) ([]chatModerationRule, error) {
	documents, err := store.firestore.Collection("chatModerationRules").Where("isActive", "==", true).Limit(500).Documents(ctx).GetAll()
	if err != nil {
		return nil, fmt.Errorf("load chat moderation rules: %w", err)
	}
	rules := make([]chatModerationRule, 0, len(documents))
	for _, document := range documents {
		data := document.Data()
		phrase := strings.TrimSpace(text(data, "phrase"))
		if phrase == "" {
			continue
		}
		rules = append(rules, chatModerationRule{
			ID: document.Ref.ID, Phrase: phrase, Language: valueOr(data, "language", "language_neutral"),
			Category: valueOr(data, "category", "profanity"), Severity: valueOr(data, "severity", "low"),
			Action: valueOr(data, "action", "mask"), MatchMode: valueOr(data, "matchMode", "word"),
			MatchVariants: booleanDefault(data, false, "matchVariants"), Aliases: stringSlice(data["aliases"]),
		})
	}
	// Longer phrases win over contained words, producing stable masking.
	sort.SliceStable(rules, func(i, j int) bool {
		return utf8.RuneCountInString(rules[i].Phrase) > utf8.RuneCountInString(rules[j].Phrase)
	})
	return rules, nil
}

func maskModeratedPhrase(input, phrase string) (string, bool) {
	return maskModeratedPhraseAdvanced(input, phrase, "word", false)
}

func maskModeratedPhraseAdvanced(input, phrase, matchMode string, matchVariants bool) (string, bool) {
	phrase = strings.TrimSpace(phrase)
	if input == "" || phrase == "" {
		return input, false
	}
	pattern := regexp.QuoteMeta(phrase)
	if matchVariants {
		var expanded strings.Builder
		for _, character := range phrase {
			expanded.WriteString(regexp.QuoteMeta(string(character)))
			if wordRune(character) {
				expanded.WriteString("+")
			}
		}
		pattern = expanded.String()
	}
	matcher, err := regexp.Compile("(?i)" + pattern)
	if err != nil {
		return input, false
	}
	indices := matcher.FindAllStringIndex(input, -1)
	if len(indices) == 0 {
		return input, false
	}
	var builder strings.Builder
	last, matched := 0, false
	for _, pair := range indices {
		start, end := pair[0], pair[1]
		if matchMode != "substring" && !moderationBoundary(input, start, end) {
			continue
		}
		builder.WriteString(input[last:start])
		builder.WriteString(maskModeratedText(input[start:end]))
		last, matched = end, true
	}
	if !matched {
		return input, false
	}
	builder.WriteString(input[last:])
	return builder.String(), true
}

func moderationBoundary(input string, start, end int) bool {
	if start > 0 {
		previous, _ := utf8.DecodeLastRuneInString(input[:start])
		first, _ := utf8.DecodeRuneInString(input[start:end])
		if wordRune(previous) && wordRune(first) {
			return false
		}
	}
	if end < len(input) {
		last, _ := utf8.DecodeLastRuneInString(input[start:end])
		next, _ := utf8.DecodeRuneInString(input[end:])
		if wordRune(last) && wordRune(next) {
			return false
		}
	}
	return true
}

func wordRune(value rune) bool { return unicode.IsLetter(value) || unicode.IsDigit(value) }

func maskModeratedText(value string) string {
	var builder strings.Builder
	visible := false
	for _, character := range value {
		if unicode.IsLetter(character) || unicode.IsDigit(character) {
			if !visible {
				builder.WriteRune(character)
				visible = true
			} else {
				builder.WriteRune('*')
			}
		} else {
			builder.WriteRune(character)
			visible = false
		}
	}
	return builder.String()
}

func normalizedModerationAliases(value any, phrase string) []string {
	if value == nil {
		return []string{}
	}
	raw := stringSlice(value)
	if len(raw) > 25 {
		return nil
	}
	seen := map[string]bool{strings.ToLower(strings.TrimSpace(phrase)): true}
	aliases := make([]string, 0, len(raw))
	for _, entry := range raw {
		alias := strings.TrimSpace(entry)
		length := utf8.RuneCountInString(alias)
		if length < 2 || length > 40 {
			return nil
		}
		normalized := strings.ToLower(alias)
		if seen[normalized] {
			continue
		}
		seen[normalized] = true
		aliases = append(aliases, alias)
	}
	return aliases
}

func chatModerationIncidentData(input chatModerationIncidentInput, incidentID string, now time.Time) map[string]any {
	matches := make([]map[string]any, 0, len(input.Matches))
	severity := "low"
	for _, match := range input.Matches {
		matches = append(matches, map[string]any{
			"ruleId": match.RuleID, "phrase": match.Phrase, "language": match.Language,
			"category": match.Category, "severity": match.Severity, "action": match.Action,
			"matchMode": match.MatchMode, "matchVariants": match.MatchVariants,
		})
		if moderationSeverityRank(match.Severity) > moderationSeverityRank(severity) {
			severity = match.Severity
		}
	}
	senderRole := participantRole(input.Booking, input.SenderID)
	senderName := valueOr(input.Booking, "passengerName", "Passenger")
	if senderRole == "driver" {
		senderName = valueOr(input.Booking, "driverName", "Driver")
	}
	reviewAudience := []string{"developer_admin"}
	if senderRole == "driver" {
		reviewAudience = append(reviewAudience, "toda_admin")
	}
	return map[string]any{
		"incidentId": incidentID, "bookingId": input.BookingID, "messageId": input.MessageID,
		"senderId": input.SenderID, "senderName": senderName, "senderRole": senderRole, "reviewAudience": reviewAudience,
		"todaId": text(input.Booking, "todaId", "driverTodaId"), "messageType": input.MessageType,
		"originalText": input.OriginalText, "displayText": input.DisplayText, "mediaPath": input.MediaPath,
		"mediaEvidencePath": input.MediaEvidencePath,
		"matches":           matches, "severity": severity, "deliveryStatus": input.DeliveryStatus,
		"status": "open", "hidden": false, "createdAt": now, "updatedAt": now,
		"purgeAt": now.Add(180 * 24 * time.Hour),
	}
}

func actorCanAccessChatIncident(actor adminIdentity, incident map[string]any) bool {
	audience := stringSlice(incident["reviewAudience"])
	todaReview := contains(audience, "toda_admin") || (len(audience) == 0 && text(incident, "senderRole") == "driver")
	return actor.developer() || (actor.TodaID != "" && actor.TodaID == text(incident, "todaId") && todaReview)
}

func moderationSeverityRank(value string) int {
	return map[string]int{"low": 1, "medium": 2, "high": 3, "critical": 4}[value]
}

func (store *Store) createChatModerationIncident(ctx context.Context, input chatModerationIncidentInput) (string, error) {
	incidentID := "chat_incident_" + strings.ReplaceAll(uuid.NewString(), "-", "")
	if input.DeliveryStatus == "reported" && input.MediaPath != "" {
		// Preserve the photo when it still exists. A late report remains valid
		// even if the normal 48-hour photo lifecycle has already removed it.
		if evidencePath, retainErr := store.retainChatPhotoEvidence(ctx, input.MediaPath, incidentID, input.BookingID, input.MessageID); retainErr == nil {
			input.MediaEvidencePath = evidencePath
		}
	}
	_, err := store.firestore.Collection("chatModerationIncidents").Doc(incidentID).Create(ctx, chatModerationIncidentData(input, incidentID, time.Now().UTC()))
	return incidentID, err
}

func (store *Store) retainChatPhotoEvidence(ctx context.Context, sourcePath, incidentID, bookingID, messageID string) (string, error) {
	if !strings.HasPrefix(sourcePath, "final/chat/"+safeObjectSegment(bookingID)+"/"+safeObjectSegment(messageID)+"/") || strings.Contains(sourcePath, "..") {
		return "", fmt.Errorf("%w: reported chat photo reference is invalid", app.ErrPrecondition)
	}
	attrs, err := store.bucket.Object(sourcePath).Attrs(ctx)
	if err != nil {
		return "", fmt.Errorf("%w: reported chat photo is no longer available", app.ErrPrecondition)
	}
	evidencePath := fmt.Sprintf("final/chat_evidence/%s/%s%s", safeObjectSegment(incidentID), uuid.NewString(), path.Ext(sourcePath))
	copier := store.bucket.Object(evidencePath).CopierFrom(store.bucket.Object(sourcePath))
	copier.ContentType = attrs.ContentType
	copier.Metadata = map[string]string{
		"incidentId": incidentID, "bookingId": bookingID, "messageId": messageID,
		"evidenceType": "reported_chat_photo", "retainedAt": time.Now().UTC().Format(time.RFC3339Nano),
	}
	if _, err := copier.Run(ctx); err != nil {
		return "", fmt.Errorf("retain reported chat photo: %w", err)
	}
	return evidencePath, nil
}

// ReportRideChatMessage creates protected safety evidence for a received ride message.
func (store *Store) ReportRideChatMessage(ctx context.Context, principal app.Principal, command app.OperationCommand) (map[string]any, error) {
	bookingID, messageID := text(command.Payload, "bookingId"), text(command.Payload, "messageId")
	booking, err := store.participantBooking(ctx, principal, bookingID)
	if err != nil {
		return nil, err
	}
	message, err := store.firestore.Collection("chat").Doc(bookingID).Collection("messages").Doc(messageID).Get(ctx)
	if err != nil || text(message.Data(), "senderId") == principal.UID {
		return nil, fmt.Errorf("%w: only a received ride message can be reported", app.ErrPrecondition)
	}
	data := message.Data()
	input := chatModerationIncidentInput{
		Booking: booking, BookingID: bookingID, MessageID: messageID, SenderID: text(data, "senderId"),
		OriginalText: text(data, "text"), DisplayText: text(data, "text"), MessageType: valueOr(data, "messageType", "text"),
		MediaPath: text(data, "mediaPath"), DeliveryStatus: "reported",
		Matches: []chatModerationMatch{{RuleID: "participant_report", Phrase: "", Language: "language_neutral", Category: valueOr(command.Payload, "category", "other"), Severity: "high", Action: "flag"}},
	}
	incidentID, err := store.createChatModerationIncident(ctx, input)
	return map[string]any{"incidentId": incidentID, "reported": err == nil}, err
}

func requireDeveloperChatSafety(actor adminIdentity) error {
	if !actor.developer() {
		return fmt.Errorf("%w: System Admin access is required", app.ErrPrecondition)
	}
	return nil
}

func (store *Store) adminListChatModerationRules(ctx context.Context, actor adminIdentity) (map[string]any, error) {
	if err := requireDeveloperChatSafety(actor); err != nil {
		return nil, err
	}
	documents, err := store.firestore.Collection("chatModerationRules").OrderBy("updatedAt", firestore.Desc).Limit(500).Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	items := make([]map[string]any, 0, len(documents))
	for _, document := range documents {
		item := document.Data()
		item["ruleId"] = document.Ref.ID
		items = append(items, item)
	}
	return map[string]any{"items": items}, nil
}

func (store *Store) adminUpsertChatModerationRule(ctx context.Context, actor adminIdentity, payload map[string]any) (map[string]any, error) {
	if err := requireDeveloperChatSafety(actor); err != nil {
		return nil, err
	}
	phrase := strings.TrimSpace(text(payload, "phrase"))
	language, category, severity, action := valueOr(payload, "language", "language_neutral"), valueOr(payload, "category", "profanity"), valueOr(payload, "severity", "low"), valueOr(payload, "action", "mask")
	matchMode := valueOr(payload, "matchMode", "word")
	aliases := normalizedModerationAliases(payload["aliases"], phrase)
	if utf8.RuneCountInString(phrase) < 2 || utf8.RuneCountInString(phrase) > 80 || !contains([]string{"low", "medium", "high", "critical"}, severity) || !contains([]string{"mask", "flag", "block"}, action) || !contains([]string{"word", "substring"}, matchMode) {
		return nil, fmt.Errorf("%w: moderation rule is invalid", app.ErrInvalidArgument)
	}
	if aliases == nil {
		return nil, fmt.Errorf("%w: moderation aliases must contain at most 25 entries of 2 to 40 characters", app.ErrInvalidArgument)
	}
	ruleID := text(payload, "ruleId")
	if ruleID == "" {
		ruleID = "chat_rule_" + strings.ReplaceAll(uuid.NewString(), "-", "")
	}
	duplicates, err := store.firestore.Collection("chatModerationRules").Where("normalizedPhrase", "==", strings.ToLower(phrase)).Limit(5).Documents(ctx).GetAll()
	if err != nil {
		return nil, fmt.Errorf("check duplicate moderation rule: %w", err)
	}
	for _, duplicate := range duplicates {
		if duplicate.Ref.ID != ruleID {
			return nil, fmt.Errorf("%w: a moderation rule for this phrase already exists", app.ErrPrecondition)
		}
	}
	now := time.Now().UTC()
	data := map[string]any{"ruleId": ruleID, "phrase": phrase, "normalizedPhrase": strings.ToLower(phrase), "aliases": aliases, "language": truncate(language, 40), "category": truncate(category, 40), "severity": severity, "action": action, "matchMode": matchMode, "matchVariants": booleanDefault(payload, false, "matchVariants"), "isActive": booleanDefault(payload, true, "isActive"), "updatedBy": actor.UID, "updatedAt": now}
	ref := store.firestore.Collection("chatModerationRules").Doc(ruleID)
	if existing, readErr := ref.Get(ctx); readErr != nil && isNotFound(readErr) {
		data["createdBy"], data["createdAt"] = actor.UID, now
	} else if readErr == nil {
		data["createdAt"] = existing.Data()["createdAt"]
	} else {
		return nil, fmt.Errorf("load moderation rule: %w", readErr)
	}
	_, err = ref.Set(ctx, data, firestore.MergeAll)
	return map[string]any{"ruleId": ruleID, "updated": err == nil}, err
}

func (store *Store) adminArchiveChatModerationRule(ctx context.Context, actor adminIdentity, payload map[string]any) (map[string]any, error) {
	if err := requireDeveloperChatSafety(actor); err != nil {
		return nil, err
	}
	ruleID := text(payload, "ruleId")
	if ruleID == "" {
		return nil, fmt.Errorf("%w: ruleId is required", app.ErrInvalidArgument)
	}
	_, err := store.firestore.Collection("chatModerationRules").Doc(ruleID).Set(ctx, map[string]any{"isActive": false, "archivedBy": actor.UID, "archivedAt": time.Now().UTC(), "updatedAt": time.Now().UTC()}, firestore.MergeAll)
	return map[string]any{"updated": err == nil}, err
}

func (store *Store) adminListChatModerationIncidents(ctx context.Context, actor adminIdentity) (map[string]any, error) {
	query := store.firestore.Collection("chatModerationIncidents").Query
	if actor.developer() {
		query = query.OrderBy("createdAt", firestore.Desc)
	} else {
		query = query.Where("todaId", "==", actor.TodaID)
	}
	documents, err := query.Limit(200).Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	items := make([]map[string]any, 0, len(documents))
	for _, document := range documents {
		item := document.Data()
		if !actorCanAccessChatIncident(actor, item) {
			continue
		}
		item["incidentId"] = document.Ref.ID
		items = append(items, item)
	}
	if !actor.developer() {
		sort.SliceStable(items, func(i, j int) bool { return storedTime(items[i]["createdAt"]).After(storedTime(items[j]["createdAt"])) })
	}
	return map[string]any{"items": items}, nil
}

func (store *Store) adminUpdateChatModerationIncident(ctx context.Context, actor adminIdentity, payload map[string]any) (map[string]any, error) {
	incidentID, action := text(payload, "incidentId"), text(payload, "action")
	if incidentID == "" || !contains([]string{"dismiss", "resolve", "hide"}, action) {
		return nil, fmt.Errorf("%w: incident action is invalid", app.ErrInvalidArgument)
	}
	ref := store.firestore.Collection("chatModerationIncidents").Doc(incidentID)
	incident, err := ref.Get(ctx)
	if err != nil {
		return nil, fmt.Errorf("%w: chat incident not found", app.ErrPrecondition)
	}
	if !actorCanAccessChatIncident(actor, incident.Data()) {
		return nil, fmt.Errorf("%w: chat incident is outside administrator scope", app.ErrPrecondition)
	}
	now, status := time.Now().UTC(), "resolved"
	if action == "dismiss" {
		status = "dismissed"
	}
	batch := store.firestore.Batch()
	updates := map[string]any{"status": status, "resolutionAction": action, "resolutionNote": truncate(text(payload, "note"), 1000), "resolvedBy": actor.UID, "resolvedAt": now, "updatedAt": now}
	if text(incident.Data(), "mediaEvidencePath") != "" {
		updates["mediaEvidencePath"] = firestore.Delete
		updates["evidenceReleasedAt"] = now
	}
	if action == "hide" {
		updates["hidden"] = true
		data := incident.Data()
		// A blocked message was never delivered or stored, so do not create a
		// synthetic chat document while resolving its incident.
		if text(data, "deliveryStatus") != "blocked" {
			messageRef := store.firestore.Collection("chat").Doc(text(data, "bookingId")).Collection("messages").Doc(text(data, "messageId"))
			batch.Set(messageRef, map[string]any{"hidden": true, "text": "Message hidden by System Admin.", "mediaPath": "", "moderationStatus": "hidden", "updatedAt": now}, firestore.MergeAll)
		}
	}
	batch.Set(ref, updates, firestore.MergeAll)
	_, err = batch.Commit(ctx)
	if err == nil {
		evidencePath := text(incident.Data(), "mediaEvidencePath")
		if evidencePath != "" {
			// Resolution ends the evidence hold. The 180-day bucket lifecycle is
			// the fallback if this best-effort deletion is interrupted.
			_ = store.bucket.Object(evidencePath).Delete(ctx)
		}
	}
	return map[string]any{"updated": err == nil}, err
}

func (store *Store) adminGetChatModerationMediaURL(ctx context.Context, actor adminIdentity, payload map[string]any) (map[string]any, error) {
	incident, err := store.firestore.Collection("chatModerationIncidents").Doc(text(payload, "incidentId")).Get(ctx)
	if err != nil || !actorCanAccessChatIncident(actor, incident.Data()) {
		return nil, fmt.Errorf("%w: chat incident media is outside administrator scope", app.ErrPrecondition)
	}
	reference := text(incident.Data(), "mediaEvidencePath")
	if reference == "" || !strings.HasPrefix(reference, "final/chat_evidence/"+safeObjectSegment(incident.Ref.ID)+"/") || strings.Contains(reference, "..") {
		return nil, fmt.Errorf("%w: this incident has no retained chat photo", app.ErrPrecondition)
	}
	if _, err := store.bucket.Object(reference).Attrs(ctx); err != nil {
		return nil, fmt.Errorf("%w: retained chat photo is unavailable", app.ErrPrecondition)
	}
	expiresAt := time.Now().Add(5 * time.Minute)
	url, err := store.bucket.SignedURL(reference, &gcs.SignedURLOptions{Scheme: gcs.SigningSchemeV4, Method: "GET", Expires: expiresAt})
	if err != nil {
		return nil, fmt.Errorf("create short-lived chat evidence URL: %w", err)
	}
	return map[string]any{"url": url, "expiresAt": expiresAt}, nil
}
