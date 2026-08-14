import {
  addMonthsToIsoDate,
  addYearsToIsoDate,
  addOneYearMinusOneDay,
  endDateForMonthlyCycles,
  floorMonthlyEndDate,
  alignMonthlyEndDate,
  adjustMonthlyEndByCycles,
  countBillingCycles,
  calculateLineAmount,
  endOfMonthlyPeriodIsoDate,
  BILLING_TYPE_RECURRING
} from "c/estimateLineItemUtils";

describe("addMonthsToIsoDate sticky month boundary", () => {
  it("keeps calendar month-end when adding months", () => {
    expect(addMonthsToIsoDate("2025-01-31", 1)).toBe("2025-02-28");
    expect(addMonthsToIsoDate("2025-02-28", 1)).toBe("2025-03-31");
    expect(addMonthsToIsoDate("2025-03-31", 1)).toBe("2025-04-30");
  });

  it("keeps calendar month-end when subtracting months", () => {
    expect(addMonthsToIsoDate("2025-03-31", -1)).toBe("2025-02-28");
    expect(addMonthsToIsoDate("2025-02-28", -1)).toBe("2025-01-31");
  });

  it("keeps calendar month-start", () => {
    expect(addMonthsToIsoDate("2025-03-01", 1)).toBe("2025-04-01");
    expect(addMonthsToIsoDate("2025-03-01", -1)).toBe("2025-02-01");
  });

  it("keeps mid-month day with clamp only", () => {
    expect(addMonthsToIsoDate("2025-03-15", 1)).toBe("2025-04-15");
    expect(addMonthsToIsoDate("2025-01-30", 1)).toBe("2025-02-28");
  });
});

describe("addYearsToIsoDate sticky month boundary", () => {
  it("keeps calendar month-end across leap years", () => {
    expect(addYearsToIsoDate("2024-02-29", 1)).toBe("2025-02-28");
    expect(addYearsToIsoDate("2025-02-28", 1)).toBe("2026-02-28");
    expect(addYearsToIsoDate("2025-01-31", 1)).toBe("2026-01-31");
  });

  it("keeps calendar month-start and mid-month", () => {
    expect(addYearsToIsoDate("2025-03-01", 1)).toBe("2026-03-01");
    expect(addYearsToIsoDate("2025-03-15", 1)).toBe("2026-03-15");
  });
});

describe("endDateForMonthlyCycles is the canonical N-month end", () => {
  it("matches month-start calendar year for 12 cycles", () => {
    expect(endDateForMonthlyCycles("2025-03-01", 12)).toBe("2026-02-28");
    expect(addOneYearMinusOneDay("2025-03-01")).toBe("2026-02-28");
  });

  it("uses 12th period end for month-end starts (not calendar year-1d)", () => {
    expect(endDateForMonthlyCycles("2025-01-31", 12)).toBe("2026-01-27");
    expect(addOneYearMinusOneDay("2025-01-31")).toBe("2026-01-27");
    expect(countBillingCycles("2025-01-31", "2026-01-27")).toBe(12);
  });

  it("floors misaligned end down, never stretches to 13", () => {
    expect(floorMonthlyEndDate("2025-01-31", "2026-01-30")).toBe("2026-01-27");
    expect(alignMonthlyEndDate("2025-01-31", "2026-01-30")).toBe("2026-01-27");
    expect(countBillingCycles("2025-01-31", "2026-01-30")).toBe(-1);
    expect(
      calculateLineAmount({
        billingType: BILLING_TYPE_RECURRING,
        quantity: 1,
        unitPrice: 10000,
        startDate: "2025-01-31",
        endDate: "2026-01-30"
      })
    ).toBeNull();
    expect(
      calculateLineAmount({
        billingType: BILLING_TYPE_RECURRING,
        quantity: 1,
        unitPrice: 10000,
        startDate: "2025-01-31",
        endDate: "2026-01-27"
      })
    ).toBe(120000);
  });

  it("adjusts end by cycle deltas from the start anchor", () => {
    expect(adjustMonthlyEndByCycles("2025-01-31", "2026-01-27", 1)).toBe(
      "2026-02-27"
    );
    expect(adjustMonthlyEndByCycles("2025-01-31", "2026-01-30", 0)).toBe(
      "2026-01-30"
    );
    expect(adjustMonthlyEndByCycles("2025-01-31", "2026-01-30", 12)).toBe(
      "2027-01-27"
    );
  });

  it("keeps anniversary endOfMonthlyPeriod clamp semantics", () => {
    // Feb 28 +1m clamp → Mar 28, then -1d → Mar 27 (not sticky Mar 31-1)
    expect(endOfMonthlyPeriodIsoDate("2025-02-28")).toBe("2025-03-27");
  });
});
