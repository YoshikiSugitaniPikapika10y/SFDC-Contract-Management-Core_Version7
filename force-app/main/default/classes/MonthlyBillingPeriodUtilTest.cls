@IsTest
private class MonthlyBillingPeriodUtilTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

    @IsTest
    static void countMonthlyCycles_matchesFullYear() {
        Date startDate = Date.newInstance(2025, 1, 1);
        Date endDate = Date.newInstance(2025, 12, 31);

        System.assertEquals(
            12,
            MonthlyBillingPeriodUtil.countMonthlyCycles(startDate, endDate)
        );
    }

    @IsTest
    static void endDateForMonthlyCycles_monthStartAndMonthEnd() {
        System.assertEquals(
            Date.newInstance(2025, 12, 31),
            MonthlyBillingPeriodUtil.endDateForMonthlyCycles(
                Date.newInstance(2025, 1, 1),
                12
            )
        );
        System.assertEquals(
            Date.newInstance(2026, 1, 27),
            MonthlyBillingPeriodUtil.endDateForMonthlyCycles(
                Date.newInstance(2025, 1, 31),
                12
            )
        );
        System.assertEquals(
            12,
            MonthlyBillingPeriodUtil.countMonthlyCycles(
                Date.newInstance(2025, 1, 31),
                Date.newInstance(2026, 1, 27)
            )
        );
    }

    @IsTest
    static void buildMonthlyPeriods_returnsAlignedPeriods() {
        Date startDate = Date.newInstance(2025, 1, 15);
        Date endDate = Date.newInstance(2025, 3, 14);

        List<MonthlyBillingPeriodUtil.BillingPeriod> periods =
            MonthlyBillingPeriodUtil.buildMonthlyPeriods(startDate, endDate);

        System.assertEquals(2, periods.size());
        System.assertEquals(startDate, periods[0].startDate);
        System.assertEquals(Date.newInstance(2025, 2, 14), periods[0].endDate);
        System.assertEquals(Date.newInstance(2025, 2, 15), periods[1].startDate);
        System.assertEquals(endDate, periods[1].endDate);
    }

    @IsTest
    static void buildMonthlyPeriods_doesNotStretchMisalignedEndDate() {
        Date startDate = Date.newInstance(2025, 1, 31);
        Date endDate = Date.newInstance(2026, 1, 30);

        List<MonthlyBillingPeriodUtil.BillingPeriod> periods =
            MonthlyBillingPeriodUtil.buildMonthlyPeriods(startDate, endDate);

        System.assertEquals(12, periods.size());
        System.assertEquals(
            Date.newInstance(2026, 1, 27),
            periods[11].endDate
        );
        System.assertEquals(
            -1,
            MonthlyBillingPeriodUtil.countMonthlyCycles(startDate, endDate)
        );
    }

    @IsTest
    static void floorMonthlyEndDate_snapsDownNotUp() {
        Date startDate = Date.newInstance(2025, 1, 31);
        Date endDate = Date.newInstance(2026, 1, 30);

        System.assertEquals(
            Date.newInstance(2026, 1, 27),
            MonthlyBillingPeriodUtil.floorMonthlyEndDate(startDate, endDate)
        );
        System.assertEquals(
            Date.newInstance(2026, 1, 27),
            MonthlyBillingPeriodUtil.alignMonthlyEndDate(startDate, endDate)
        );
    }

    @IsTest
    static void buildCalendarMonthPeriods_splitsByCalendarMonth() {
        Date startDate = Date.newInstance(2026, 6, 15);
        Date endDate = Date.newInstance(2027, 5, 31);

        List<MonthlyBillingPeriodUtil.BillingPeriod> periods =
            MonthlyBillingPeriodUtil.buildCalendarMonthPeriods(startDate, endDate);

        System.assertEquals(12, periods.size());
        System.assertEquals(startDate, periods[0].startDate);
        System.assertEquals(Date.newInstance(2026, 6, 30), periods[0].endDate);
        System.assertEquals(Date.newInstance(2026, 7, 1), periods[1].startDate);
        System.assertEquals(Date.newInstance(2026, 7, 31), periods[1].endDate);
        System.assertEquals(Date.newInstance(2027, 5, 1), periods[11].startDate);
        System.assertEquals(endDate, periods[11].endDate);
    }

    @IsTest
    static void endOfCalendarMonth_returnsLastDayOfMonth() {
        System.assertEquals(
            Date.newInstance(2026, 2, 28),
            MonthlyBillingPeriodUtil.endOfCalendarMonth(Date.newInstance(2026, 2, 10))
        );
    }

    @IsTest
    static void isMonthlyPeriodStartDate_matchesAnniversaryStarts() {
        Date anchor = Date.newInstance(2026, 4, 15);

        System.assertEquals(
            true,
            MonthlyBillingPeriodUtil.isMonthlyPeriodStartDate(
                anchor,
                Date.newInstance(2026, 10, 15)
            )
        );
        System.assertEquals(
            false,
            MonthlyBillingPeriodUtil.isMonthlyPeriodStartDate(
                anchor,
                Date.newInstance(2026, 10, 20)
            )
        );
        System.assertEquals(
            true,
            MonthlyBillingPeriodUtil.isMonthlyPeriodStartDate(anchor, anchor)
        );
    }

    @IsTest
    static void invalidDates_returnSafeDefaults() {
        System.assertEquals(-1, MonthlyBillingPeriodUtil.countMonthlyCycles(null, Date.today()));
        System.assertEquals(-1, MonthlyBillingPeriodUtil.countMonthlyCycles(Date.today(), null));
        System.assertEquals(0, MonthlyBillingPeriodUtil.buildMonthlyPeriods(null, Date.today()).size());
        System.assertEquals(
            Date.newInstance(2025, 2, 28),
            MonthlyBillingPeriodUtil.endOfMonthlyPeriod(Date.newInstance(2025, 2, 1))
        );
        System.assertEquals(
            null,
            MonthlyBillingPeriodUtil.endDateForMonthlyCycles(
                Date.newInstance(2025, 1, 1),
                0
            )
        );
        System.assertEquals(
            null,
            MonthlyBillingPeriodUtil.endDateForMonthlyCycles(
                Date.newInstance(2025, 1, 1),
                null
            )
        );
        System.assertEquals(
            null,
            MonthlyBillingPeriodUtil.floorMonthlyEndDate(
                Date.newInstance(2025, 3, 1),
                Date.newInstance(2025, 2, 1)
            )
        );
        System.assertEquals(
            null,
            MonthlyBillingPeriodUtil.endOfCalendarMonth(null)
        );
        System.assertEquals(
            0,
            MonthlyBillingPeriodUtil.buildCalendarMonthPeriods(
                Date.newInstance(2025, 3, 1),
                Date.newInstance(2025, 2, 1)
            ).size()
        );
        System.assertEquals(
            false,
            MonthlyBillingPeriodUtil.isMonthlyPeriodStartDate(
                Date.newInstance(2025, 1, 1),
                Date.newInstance(2024, 12, 1)
            )
        );
    }

    @IsTest
    static void resolveMonthlyEndDate_aliasesAlign() {
        Date startDate = Date.newInstance(2025, 1, 15);
        Date alignedEnd = Date.newInstance(2025, 3, 14);
        Date misalignedEnd = Date.newInstance(2025, 3, 20);

        System.assertEquals(
            alignedEnd,
            MonthlyBillingPeriodUtil.resolveMonthlyEndDate(startDate, alignedEnd)
        );
        System.assertEquals(
            alignedEnd,
            MonthlyBillingPeriodUtil.alignMonthlyEndDate(startDate, alignedEnd)
        );
        System.assertEquals(
            alignedEnd,
            MonthlyBillingPeriodUtil.resolveMonthlyEndDate(startDate, misalignedEnd)
        );
        System.assertEquals(
            misalignedEnd,
            MonthlyBillingPeriodUtil.resolveMonthlyEndDate(null, misalignedEnd)
        );
    }

    @IsTest
    static void leapYear_februaryPeriodEndsOn29() {
        // 月次期間: addMonths(1).addDays(-1)。1/31 起点はうるう年でも 2/28 になる
        // （addMonths が 2/29 に着地したあと -1 日するため）。
        System.assertEquals(
            Date.newInstance(2024, 2, 28),
            MonthlyBillingPeriodUtil.endOfMonthlyPeriod(
                Date.newInstance(2024, 1, 31)
            )
        );
        System.assertEquals(
            Date.newInstance(2024, 2, 29),
            MonthlyBillingPeriodUtil.endOfMonthlyPeriod(
                Date.newInstance(2024, 2, 1)
            )
        );
        System.assertEquals(
            Date.newInstance(2024, 2, 29),
            MonthlyBillingPeriodUtil.endDateForMonthlyCycles(
                Date.newInstance(2024, 2, 1),
                1
            )
        );
        System.assertEquals(
            Date.newInstance(2024, 2, 29),
            MonthlyBillingPeriodUtil.endOfCalendarMonth(
                Date.newInstance(2024, 2, 10)
            )
        );
    }
}
