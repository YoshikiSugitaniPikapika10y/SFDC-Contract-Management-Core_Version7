/**
 * 月次課金期間（各月の開始日・終了日）の列挙ユーティリティ。
 *
 * 月数 N の終了日は「開始から月次期間を N 回積んだ最後の終了日」を正とする。
 * 暦の「開始＋N年−1日」とは、月末開始などで一致しない場合がある。
 */
public without sharing class MonthlyBillingPeriodUtil {
  public class BillingPeriod {
    public Date startDate;
    public Date endDate;

    public BillingPeriod(Date startDate, Date endDate) {
      this.startDate = startDate;
      this.endDate = endDate;
    }
  }

  /**
   * 仕様: 日付仕様 第1.2節、第2.5節。
   * 開始日から cycles 回分の月次期間を積んだ終了日。
   */
  public static Date endDateForMonthlyCycles(Date startDate, Integer cycles) {
    if (startDate == null || cycles == null || cycles < 1) {
      return null;
    }
    Date periodStart = startDate;
    Date periodEnd;
    for (Integer i = 0; i < cycles; i++) {
      periodEnd = endOfMonthlyPeriod(periodStart);
      periodStart = periodEnd.addDays(1);
    }
    return periodEnd;
  }

  /**
   * 終了日以下で完了する最後の月次期間終了日（切り捨て寄せ）。
   * 1期間も完了しない場合は null。
   */
  public static Date floorMonthlyEndDate(Date startDate, Date endDate) {
    if (startDate == null || endDate == null || endDate < startDate) {
      return null;
    }
    Date lastCompleteEnd = null;
    Date periodStart = startDate;
    while (true) {
      Date periodEnd = endOfMonthlyPeriod(periodStart);
      if (periodEnd > endDate) {
        break;
      }
      lastCompleteEnd = periodEnd;
      if (periodEnd == endDate) {
        return endDate;
      }
      periodStart = periodEnd.addDays(1);
    }
    return lastCompleteEnd;
  }

  /**
   * 境界に乗っていればそのまま、乗っていなければ短い側へ寄せる。
   */
  public static Date alignMonthlyEndDate(Date startDate, Date endDate) {
    if (startDate == null || endDate == null) {
      return endDate;
    }
    if (countMonthlyCycles(startDate, endDate) >= 1) {
      return endDate;
    }
    return floorMonthlyEndDate(startDate, endDate);
  }

  /** 互換用。alignMonthlyEndDate と同義（長く伸ばさない）。 */
  public static Date resolveMonthlyEndDate(Date startDate, Date endDate) {
    return alignMonthlyEndDate(startDate, endDate);
  }

  /** 仕様: 日付仕様 第1.2節 */
  public static List<BillingPeriod> buildMonthlyPeriods(
    Date startDate,
    Date endDate
  ) {
    List<BillingPeriod> periods = new List<BillingPeriod>();
    if (startDate == null || endDate == null || endDate < startDate) {
      return periods;
    }

    // 終了日を先に伸ばさない。完了した期間だけを列挙する。
    Date periodStart = startDate;
    while (true) {
      Date periodEnd = endOfMonthlyPeriod(periodStart);
      if (periodEnd > endDate) {
        break;
      }
      periods.add(new BillingPeriod(periodStart, periodEnd));
      if (periodEnd == endDate) {
        break;
      }
      periodStart = periodEnd.addDays(1);
    }
    return periods;
  }

  /**
   * 仕様: Accounting 第3.3節、日付仕様 第2章
   * 開始日起点の月次バケットで終了日までを覆う。
   * 最終バケットだけ短期になってよい（認識の時間軸正本用）。
   */
  public static List<BillingPeriod> buildMonthlyPeriodsCoveringEnd(
    Date startDate,
    Date endDate
  ) {
    List<BillingPeriod> periods = buildMonthlyPeriods(startDate, endDate);
    if (startDate == null || endDate == null || endDate < startDate) {
      return periods;
    }
    Date coveredEnd = periods.isEmpty()
      ? startDate.addDays(-1)
      : periods[periods.size() - 1].endDate;
    if (coveredEnd >= endDate) {
      return periods;
    }
    Date nextStart = coveredEnd.addDays(1);
    if (nextStart > endDate) {
      return periods;
    }
    periods.add(new BillingPeriod(nextStart, endDate));
    return periods;
  }

  /** 仕様: 日付仕様 第1.2節 */
  public static Integer countMonthlyCycles(Date startDate, Date endDate) {
    if (startDate == null || endDate == null || endDate < startDate) {
      return -1;
    }

    Integer cycles = 0;
    Date periodStart = startDate;
    while (true) {
      Date periodEnd = endOfMonthlyPeriod(periodStart);
      if (periodEnd > endDate) {
        return -1;
      }
      cycles++;
      if (periodEnd == endDate) {
        return cycles;
      }
      periodStart = periodEnd.addDays(1);
    }
    return -1;
  }

  /** 仕様: 日付仕様 第1.1節、第1.2節 */
  public static Date endOfMonthlyPeriod(Date periodStart) {
    return periodStart.addMonths(1).addDays(-1);
  }

  public static Boolean isMonthlyPeriodStartDate(
    Date anchorStartDate,
    Date candidateDate
  ) {
    if (
      anchorStartDate == null ||
      candidateDate == null ||
      candidateDate < anchorStartDate
    ) {
      return false;
    }

    Date periodStart = anchorStartDate;
    while (periodStart <= candidateDate) {
      if (periodStart == candidateDate) {
        return true;
      }
      periodStart = endOfMonthlyPeriod(periodStart).addDays(1);
    }
    return false;
  }

  public static Date endOfCalendarMonth(Date referenceDate) {
    if (referenceDate == null) {
      return null;
    }
    return Date.newInstance(referenceDate.year(), referenceDate.month(), 1)
      .addMonths(1)
      .addDays(-1);
  }

  /** 仕様: Accounting 第3.3節、日付仕様 第2章 */
  public static List<BillingPeriod> buildCalendarMonthPeriods(
    Date startDate,
    Date endDate
  ) {
    List<BillingPeriod> periods = new List<BillingPeriod>();
    if (startDate == null || endDate == null || endDate < startDate) {
      return periods;
    }

    Date periodStart = startDate;
    while (periodStart <= endDate) {
      Date calendarMonthEnd = endOfCalendarMonth(periodStart);
      Date periodEnd = calendarMonthEnd > endDate ? endDate : calendarMonthEnd;
      periods.add(new BillingPeriod(periodStart, periodEnd));
      if (periodEnd == endDate) {
        break;
      }
      periodStart = periodEnd.addDays(1);
    }
    return periods;
  }
}
