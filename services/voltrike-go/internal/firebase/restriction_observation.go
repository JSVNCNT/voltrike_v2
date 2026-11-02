package firebase

// nextRestrictionObservation preserves the retired RTDB monitor's GPS-clock
// deduplication, two-fix confirmation, and one-minute reentry cooldown. State
// field names remain compatible with observations committed by that monitor.
func nextRestrictionObservation(state map[string]any, inside bool, observedAt, now int64) (string, map[string]any) {
	if observedAt <= 0 || observedAt <= int64(number(state, "lastProcessedObservedAt")) {
		return "ignored", nil
	}
	updates := map[string]any{"lastProcessedObservedAt": observedAt, "lastObservedFixAt": observedAt}
	if inside {
		if booleanDefault(state, false, "inside") {
			updates["candidateOutsideSamples"], updates["lastInsideObservedAt"] = 0, observedAt
			return "inside", updates
		}
		samples := 1
		if previous := int64(number(state, "lastInsideObservedAt")); previous > 0 && observedAt > previous {
			samples += integer(state, "candidateInsideSamples")
		}
		first := observedAt
		if integer(state, "candidateInsideSamples") > 0 && number(state, "firstInsideObservedAt") > 0 {
			first = int64(number(state, "firstInsideObservedAt"))
		}
		updates["inside"], updates["candidateInsideSamples"] = false, samples
		updates["firstInsideObservedAt"], updates["lastInsideObservedAt"] = first, observedAt
		updates["candidateOutsideSamples"] = 0
		if samples < 2 {
			return "candidate_entry", updates
		}
		if now < int64(number(state, "reentryAllowedAtMillis")) {
			updates["candidateInsideSamples"] = 2
			return "reentry_cooldown", updates
		}
		updates["inside"], updates["candidateInsideSamples"] = true, 0
		updates["firstInsideObservedAt"], updates["reentryAllowedAtMillis"] = nil, 0
		return "enter", updates
	}
	updates["candidateInsideSamples"], updates["firstInsideObservedAt"] = 0, nil
	updates["lastOutsideObservedAt"] = observedAt
	if booleanDefault(state, false, "inside") {
		samples := 1
		if previous := int64(number(state, "lastOutsideObservedAt")); previous > 0 && observedAt > previous {
			samples += integer(state, "candidateOutsideSamples")
		}
		updates["candidateOutsideSamples"] = samples
		if samples < 2 {
			return "candidate_exit", updates
		}
		updates["inside"], updates["candidateOutsideSamples"] = false, 0
		updates["reentryAllowedAtMillis"] = now + 60000
		return "exit", updates
	}
	updates["inside"], updates["candidateOutsideSamples"] = false, 0
	return "outside", updates
}
