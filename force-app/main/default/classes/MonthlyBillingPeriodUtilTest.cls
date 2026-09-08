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
      MonthlyBillingPeriodUtil.countMonthlyCycles(startDate, endDate),
      '共通基盤 第1.1節: 1/1開始の12サイクル終了は同年12/31'
    );
  }

  @IsTest
  static void endDateForMonthlyCycles_monthStartAndMonthEnd() {
    System.assertEquals(
      Date.newInstance(2025, 12, 31),
      MonthlyBillingPeriodUtil.endDateForMonthlyCycles(
        Date.newInstance(2025, 1, 1),
        12
      ),
      '共通基盤 第1.1節: 1/1開始12サイクルは12/31'
    );
    System.assertEquals(
      Date.newInstance(2026, 1, 27),
      MonthlyBillingPeriodUtil.endDateForMonthlyCycles(
        Date.newInstance(2025, 1, 31),
        12
      ),
      '共通基盤 第1.1節: 2025/1/31開始の12サイクル終了は2026/1/27。一発addMonths(12)ではない'
    );
    System.assertEquals(
      Date.newInstance(2025, 2, 27),
      MonthlyBillingPeriodUtil.endOfMonthlyPeriod(Date.newInstance(2025, 1, 31)),
      '共通基盤 第1.1節: 2025/1/31の1サイクル終了は2/27'
    );
    System.assertEquals(
      Date.newInstance(2025, 2, 28),
      MonthlyBillingPeriodUtil.endOfMonthlyPeriod(Date.newInstance(2025, 1, 31))
        .addDays(1),
      '共通基盤 第1.1節: 次サイクル開始は直前終了の翌日 2/28'
    );
    System.assertEquals(
      Date.newInstance(2025, 3, 27),
      MonthlyBillingPeriodUtil.endDateForMonthlyCycles(
        Date.newInstance(2025, 1, 31),
        2
      ),
      '共通基盤 第1.1節: 2025/1/31の2サイクル終了は3/27'
    );
    System.assertEquals(
      Date.newInstance(2025, 4, 27),
      MonthlyBillingPeriodUtil.endDateForMonthlyCycles(
        Date.newInstance(2025, 1, 31),
        3
      ),
      '共通基盤 第1.1節: 2025/1/31の3サイクル終了は4/27'
    );
    System.assertEquals(
      12,
      MonthlyBillingPeriodUtil.countMonthlyCycles(
        Date.newInstance(2025, 1, 31),
        Date.newInstance(2026, 1, 27)
      ),
      '共通基盤 第1.1節: 2025/1/31〜2026/1/27は12サイクル'
    );
  }

  @IsTest
  static void buildMonthlyPeriods_returnsAlignedPeriods() {
    Date startDate = Date.newInstance(2025, 1, 15);
    Date endDate = Date.newInstance(2025, 3, 14);

    List<MonthlyBillingPeriodUtil.BillingPeriod> periods = MonthlyBillingPeriodUtil.buildMonthlyPeriods(
      startDate,
      endDate
    );

    System.assertEquals(
      2,
      periods.size(),
      '共通基盤 第1.1節: 1/15〜3/14は2サイクル'
    );
    System.assertEquals(startDate, periods[0].startDate);
    System.assertEquals(
      Date.newInstance(2025, 2, 14),
      periods[0].endDate,
      '共通基盤 第1.1節: 1/15の1サイクル終了は2/14'
    );
    System.assertEquals(Date.newInstance(2025, 2, 15), periods[1].startDate);
    System.assertEquals(endDate, periods[1].endDate);
  }

  @IsTest
  static void buildMonthlyPeriods_doesNotStretchMisalignedEndDate() {
    Date startDate = Date.newInstance(2025, 1, 31);
    Date endDate = Date.newInstance(2026, 1, 30);

    List<MonthlyBillingPeriodUtil.BillingPeriod> periods = MonthlyBillingPeriodUtil.buildMonthlyPeriods(
      startDate,
      endDate
    );

    System.assertEquals(12, periods.size());
    System.assertEquals(
      Date.newInstance(2026, 1, 27),
      periods[11].endDate,
      '共通基盤 第2.1節: ずれた終了日は短い側の境界へ寄せる。12サイクル終了は1/27'
    );
    System.assertEquals(
      -1,
      MonthlyBillingPeriodUtil.countMonthlyCycles(startDate, endDate),
      '共通基盤 第2.1節: 境界不一致はサイクル数にならない'
    );
  }

  @IsTest
  static void floorMonthlyEndDate_snapsDownNotUp() {
    Date startDate = Date.newInstance(2025, 1, 31);
    Date endDate = Date.newInstance(2026, 1, 30);

    System.assertEquals(
      Date.newInstance(2026, 1, 27),
      MonthlyBillingPeriodUtil.floorMonthlyEndDate(startDate, endDate),
      '共通基盤 第2.1節: 短い側の境界へ寄せる'
    );
    System.assertEquals(
      Date.newInstance(2026, 1, 27),
      MonthlyBillingPeriodUtil.alignMonthlyEndDate(startDate, endDate),
      '共通基盤 第2.1節: 長く伸ばさない'
    );
  }

  @IsTest
  static void buildCalendarMonthPeriods_splitsByCalendarMonth() {
    Date startDate = Date.newInstance(2026, 6, 15);
    Date endDate = Date.newInstance(2027, 5, 31);

    List<MonthlyBillingPeriodUtil.BillingPeriod> periods = MonthlyBillingPeriodUtil.buildCalendarMonthPeriods(
      startDate,
      endDate
    );

    System.assertEquals(
      12,
      periods.size(),
      '共通基盤 第6.2節: 暦月はサービス期間が触れる暦月ごと'
    );
    System.assertEquals(startDate, periods[0].startDate);
    System.assertEquals(
      Date.newInstance(2026, 6, 30),
      periods[0].endDate,
      '共通基盤 第6.2節: 初回はサービス期間開始日、暦月末で閉じる'
    );
    System.assertEquals(Date.newInstance(2026, 7, 1), periods[1].startDate);
    System.assertEquals(Date.newInstance(2026, 7, 31), periods[1].endDate);
    System.assertEquals(Date.newInstance(2027, 5, 1), periods[11].startDate);
    System.assertEquals(
      endDate,
      periods[11].endDate,
      '共通基盤 第6.2節: 最終回は終了日で閉じる'
    );
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
    System.assertEquals(
      -1,
      MonthlyBillingPeriodUtil.countMonthlyCycles(null, Date.today())
    );
    System.assertEquals(
      -1,
      MonthlyBillingPeriodUtil.countMonthlyCycles(Date.today(), null)
    );
    System.assertEquals(
      0,
      MonthlyBillingPeriodUtil.buildMonthlyPeriods(null, Date.today()).size()
    );
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
        )
        .size()
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
  static void buildMonthlyPeriodsCoveringEnd_addsShortFinalBucket() {
    Date startDate = Date.newInstance(2025, 1, 15);
    Date endDate = Date.newInstance(2025, 3, 20);

    List<MonthlyBillingPeriodUtil.BillingPeriod> periods = MonthlyBillingPeriodUtil.buildMonthlyPeriodsCoveringEnd(
      startDate,
      endDate
    );

    System.assertEquals(
      3,
      periods.size(),
      '共通基盤 第6.2節: 契約日アンカーは最終バケットだけ終了日で閉じる'
    );
    System.assertEquals(startDate, periods[0].startDate);
    System.assertEquals(Date.newInstance(2025, 2, 14), periods[0].endDate);
    System.assertEquals(Date.newInstance(2025, 2, 15), periods[1].startDate);
    System.assertEquals(Date.newInstance(2025, 3, 14), periods[1].endDate);
    System.assertEquals(Date.newInstance(2025, 3, 15), periods[2].startDate);
    System.assertEquals(endDate, periods[2].endDate);
  }

  @IsTest
  static void leapYear_january31PassesFebruary29AsLaterStart() {
    System.assertEquals(
      Date.newInstance(2024, 2, 28),
      MonthlyBillingPeriodUtil.endOfMonthlyPeriod(Date.newInstance(2024, 1, 31)),
      '共通基盤 第1.1節: うるう年1/31の1サイクル終了は2/28'
    );
    System.assertEquals(
      true,
      MonthlyBillingPeriodUtil.isMonthlyPeriodStartDate(
        Date.newInstance(2024, 1, 31),
        Date.newInstance(2024, 2, 29)
      ),
      '共通基盤 第1.1節: うるう年1/31開始は2/29を通り、以後の起点は29日。常に28日へ寄るのではない'
    );
    System.assertEquals(
      Date.newInstance(2024, 2, 29),
      MonthlyBillingPeriodUtil.endOfMonthlyPeriod(Date.newInstance(2024, 2, 1)),
      '共通基盤 第1.1節: 2/1の1サイクル終了は2/29'
    );
    System.assertEquals(
      Date.newInstance(2024, 2, 29),
      MonthlyBillingPeriodUtil.endDateForMonthlyCycles(
        Date.newInstance(2024, 2, 1),
        1
      ),
      '共通基盤 第1.1節: 2/1の1サイクル終了は2/29'
    );
    System.assertEquals(
      Date.newInstance(2024, 2, 29),
      MonthlyBillingPeriodUtil.endOfCalendarMonth(Date.newInstance(2024, 2, 10)),
      '共通基盤 第6.2節: 暦月末はうるう年2/29'
    );
  }
}
