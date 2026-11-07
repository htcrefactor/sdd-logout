import Foundation
import Testing
@testable import LOGOUT

/// These values are test inputs only. No workout history or Health data is created.
@MainActor
struct LOGOUTTests {
    @Test func durationChangesUnitsAtMinuteAndHourBoundaries() {
        #expect(RunFormat.duration(0) == "00:00")
        #expect(RunFormat.duration(59) == "00:59")
        #expect(RunFormat.duration(60) == "01:00")
        #expect(RunFormat.duration(3_599) == "59:59")
        #expect(RunFormat.duration(3_600) == "1:00:00")
        #expect(RunFormat.duration(3_661) == "1:01:01")
    }

    @Test func durationDoesNotAddAnUnfinishedSecond() {
        #expect(RunFormat.duration(59.99) == "00:59")
        #expect(RunFormat.duration(3_599.99) == "59:59")
    }

    @Test func durationHandlesInvalidInputWithoutInventingTime() {
        #expect(RunFormat.duration(-1) == "00:00")
        #expect(RunFormat.duration(.nan) == "00:00")
        #expect(RunFormat.duration(.infinity) == "00:00")
        #expect(RunFormat.duration(-.infinity) == "00:00")
    }

    @Test func longDurationDoesNotWrapAtTwentyFourHours() {
        #expect(RunFormat.duration(86_400) == "24:00:00")
        #expect(RunFormat.duration(100 * 3_600 + 61) == "100:01:01")
    }

    @Test func missingOrInvalidPaceStaysUnavailable() {
        #expect(RunFormat.pace(nil) == "—")
        #expect(RunFormat.pace(0) == "—")
        #expect(RunFormat.pace(-300) == "—")
        #expect(RunFormat.pace(.nan) == "—")
        #expect(RunFormat.pace(.infinity) == "—")
        #expect(RunFormat.pace(3_600) == "—")
    }

    @Test func paceRoundingCarriesIntoTheNextMinute() {
        #expect(RunFormat.pace(359.4) == "5′59″")
        #expect(RunFormat.pace(359.6) == "6′00″")
        #expect(RunFormat.pace(305) == "5′05″")
    }

    @Test func distanceConvertsMetersToKilometersWithConsistentPrecision() {
        #expect(RunFormat.distance(0) == "0.00")
        #expect(RunFormat.distance(10) == "0.01")
        #expect(RunFormat.distance(1_234) == "1.23")
        #expect(RunFormat.distance(5_000) == "5.00")
        #expect(RunFormat.distance(42_195) == "42.20")
    }
}
