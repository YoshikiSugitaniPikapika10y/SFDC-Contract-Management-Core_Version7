/**
 * 請求日・入金予定日の共通計算。生成時だけ使う。
 */
public without sharing class BillingScheduleService {
  public static final String METHOD_SAME_DAY = 'SameDay';
  public static final String METHOD_ON_OR_AFTER = 'OnOrAfterSpecifiedDay';
  public static final String METHOD_MONTH_OFFSET = 'MonthOffset';
  public static final String METHOD_DAY_OFFSET = 'DayOffset';
  public static final String DAY_KIND_DAY = 'Day';
  public static final String DAY_KIND_MONTH_END = 'MonthEnd';
  public static final String ADJUST_NONE = 'None';
  public static final String ADJUST_PREVIOUS = 'Previous';
  public static final String ADJUST_NEXT = 'Next';

  public static final List<String> BILLING_ACCOUNT_SCHEDULE_FIELDS = new List<String>{
    'InvoiceDateMethod__c',
    'InvoiceDateDayKind__c',
    'InvoiceDateDayOfMonth__c',
    'InvoiceDateMonthOffset__c',
    'InvoiceDateDayOffset__c',
    'InvoiceDateAdjust__c',
    'PaymentTermMethod__c',
    'PaymentTermDayKind__c',
    'PaymentTermDayOfMonth__c',
    'PaymentTermMonthOffset__c',
    'PaymentTermDayOffset__c',
    'PaymentTermAdjust__c'
  };

  public class ScheduleException extends Exception {
  }

  /** 仕様: Core 第7.2節、第7.5節 */
  public static void assertSchedule(BillingAccount__c account) {
    if (account == null) {
      throw new ScheduleException('請求アカウントが指定されていません。');
    }
    assertInvoiceDateRule(account);
    assertPaymentTerm(account);
  }

  /** 仕様: Core 第7.2節、日付仕様 第4章 */
  public static Date computeInvoiceDate(
    BillingAccount__c account,
    Date periodStart
  ) {
    return computeInvoiceDateFromAnchor(account, periodStart);
  }

  /** 仕様: Core 第7.2節、日付仕様 第4章 */
  public static Date computeInvoiceDate(
    BillingAccount__c account,
    Date periodStart,
    Date periodEnd,
    Date contractProductStart,
    Date contractProductEnd
  ) {
    Date anchor = periodStart;
    if (anchor == null) {
      anchor = contractProductStart;
    }
    return computeInvoiceDateFromAnchor(account, anchor);
  }

  /** 仕様: Core 第7.2節、日付仕様 第4章 */
  public static Date computeInvoiceDateFromAnchor(
    BillingAccount__c account,
    Date anchorDate
  ) {
    assertInvoiceDateRule(account);
    if (anchorDate == null) {
      return null;
    }
    Date calculated = calculateInvoiceDate(account, anchorDate);
    return applyAdjust(calculated, account.InvoiceDateAdjust__c);
  }

  /** 仕様: Core 第7.5節、日付仕様 第5章。暦月／暦日。サイクル関数は使わない。 */
  public static Date computePaymentScheduledDate(
    BillingAccount__c account,
    Date invoiceDate
  ) {
    assertPaymentTerm(account);
    if (invoiceDate == null) {
      return null;
    }
    Date scheduled = calculatePaymentScheduledDate(account, invoiceDate);
    scheduled = applyAdjust(scheduled, account.PaymentTermAdjust__c);
    if (scheduled < invoiceDate) {
      throw new ScheduleException('入金予定日が請求日より前になる設定は使えません。');
    }
    return scheduled;
  }

  /** 仕様: Core 第7.2節、第7.5節 */
  public static void applySnapshots(
    Invoice__c invoice,
    BillingAccount__c account
  ) {
    if (invoice == null || account == null) {
      return;
    }
    if (String.isBlank(invoice.InvoiceDateMethodSnapShot__c)) {
      invoice.InvoiceDateMethodSnapShot__c = account.InvoiceDateMethod__c;
    }
    if (String.isBlank(invoice.InvoiceDateDayKindSnapShot__c)) {
      invoice.InvoiceDateDayKindSnapShot__c = account.InvoiceDateDayKind__c;
    }
    if (invoice.InvoiceDateDayOfMonthSnapShot__c == null) {
      invoice.InvoiceDateDayOfMonthSnapShot__c = account.InvoiceDateDayOfMonth__c;
    }
    if (invoice.InvoiceDateMonthOffsetSnapShot__c == null) {
      invoice.InvoiceDateMonthOffsetSnapShot__c = account.InvoiceDateMonthOffset__c;
    }
    if (invoice.InvoiceDateDayOffsetSnapShot__c == null) {
      invoice.InvoiceDateDayOffsetSnapShot__c = account.InvoiceDateDayOffset__c;
    }
    if (String.isBlank(invoice.InvoiceDateAdjustSnapShot__c)) {
      invoice.InvoiceDateAdjustSnapShot__c = account.InvoiceDateAdjust__c;
    }
    if (String.isBlank(invoice.PaymentTermMethodSnapShot__c)) {
      invoice.PaymentTermMethodSnapShot__c = account.PaymentTermMethod__c;
    }
    if (String.isBlank(invoice.PaymentTermDayKindSnapShot__c)) {
      invoice.PaymentTermDayKindSnapShot__c = account.PaymentTermDayKind__c;
    }
    if (invoice.PaymentTermDayOfMonthSnapShot__c == null) {
      invoice.PaymentTermDayOfMonthSnapShot__c = account.PaymentTermDayOfMonth__c;
    }
    if (invoice.PaymentTermMonthOffsetSnapShot__c == null) {
      invoice.PaymentTermMonthOffsetSnapShot__c = account.PaymentTermMonthOffset__c;
    }
    if (invoice.PaymentTermDayOffsetSnapShot__c == null) {
      invoice.PaymentTermDayOffsetSnapShot__c = account.PaymentTermDayOffset__c;
    }
    if (String.isBlank(invoice.PaymentTermAdjustSnapShot__c)) {
      invoice.PaymentTermAdjustSnapShot__c = account.PaymentTermAdjust__c;
    }
  }

  static void assertInvoiceDateRule(BillingAccount__c account) {
    if (account == null) {
      throw new ScheduleException('請求アカウントが指定されていません。');
    }
    String method = account.InvoiceDateMethod__c;
    String adjust = account.InvoiceDateAdjust__c;
    if (String.isBlank(method) || String.isBlank(adjust)) {
      throw new ScheduleException('請求日ルールの計算方式と補正は必須です。');
    }
    if (!isInvoiceDateAdjust(adjust)) {
      throw new ScheduleException('請求日の補正が不正です。');
    }
    Integer day = toInteger(account.InvoiceDateDayOfMonth__c);
    Integer monthOffset = toInteger(account.InvoiceDateMonthOffset__c);
    Integer dayOffset = toInteger(account.InvoiceDateDayOffset__c);
    String dayKind = account.InvoiceDateDayKind__c;
    if (method == METHOD_SAME_DAY) {
      assertBlank(
        '請求日ルール',
        dayKind,
        day,
        monthOffset,
        dayOffset,
        true,
        true,
        true,
        true
      );
      return;
    }
    if (method == METHOD_ON_OR_AFTER) {
      assertDayKindRequired('請求日ルール', dayKind, day);
      assertBlank('請求日ルール', dayKind, day, monthOffset, dayOffset, false, false, true, true);
      return;
    }
    if (method == METHOD_MONTH_OFFSET) {
      assertIntegerInRange('請求日の月数', monthOffset, -12, 12, true);
      assertDayKindRequired('請求日ルール', dayKind, day);
      assertBlank('請求日ルール', dayKind, day, monthOffset, dayOffset, false, false, false, true);
      return;
    }
    if (method == METHOD_DAY_OFFSET) {
      assertIntegerInRange('請求日の日数', dayOffset, -365, 365, true);
      assertBlank('請求日ルール', dayKind, day, monthOffset, dayOffset, true, true, true, false);
      return;
    }
    throw new ScheduleException('請求日の計算方式が不正です。');
  }

  static void assertPaymentTerm(BillingAccount__c account) {
    if (account == null) {
      throw new ScheduleException('請求アカウントが指定されていません。');
    }
    String method = account.PaymentTermMethod__c;
    String adjust = account.PaymentTermAdjust__c;
    if (String.isBlank(method) || String.isBlank(adjust)) {
      throw new ScheduleException('支払条件の計算方式と補正は必須です。');
    }
    if (!isInvoiceDateAdjust(adjust)) {
      throw new ScheduleException('支払条件の補正が不正です。');
    }
    Integer day = toInteger(account.PaymentTermDayOfMonth__c);
    Integer monthOffset = toInteger(account.PaymentTermMonthOffset__c);
    Integer dayOffset = toInteger(account.PaymentTermDayOffset__c);
    String dayKind = account.PaymentTermDayKind__c;
    if (method == METHOD_MONTH_OFFSET) {
      assertIntegerInRange('支払条件の月数', monthOffset, 0, 12, true);
      assertDayKindRequired('支払条件', dayKind, day);
      assertBlank('支払条件', dayKind, day, monthOffset, dayOffset, false, false, false, true);
      return;
    }
    if (method == METHOD_DAY_OFFSET) {
      assertIntegerInRange('支払条件の日数', dayOffset, 0, 365, true);
      assertBlank('支払条件', dayKind, day, monthOffset, dayOffset, true, true, true, false);
      return;
    }
    throw new ScheduleException('支払条件の計算方式が不正です。');
  }

  static Date calculateInvoiceDate(BillingAccount__c account, Date anchorDate) {
    String method = account.InvoiceDateMethod__c;
    if (method == METHOD_SAME_DAY) {
      return anchorDate;
    }
    if (method == METHOD_ON_OR_AFTER) {
      return firstOnOrAfter(anchorDate, account.InvoiceDateDayKind__c, toInteger(account.InvoiceDateDayOfMonth__c));
    }
    if (method == METHOD_MONTH_OFFSET) {
      return dateInOffsetMonth(
        anchorDate,
        toInteger(account.InvoiceDateMonthOffset__c),
        account.InvoiceDateDayKind__c,
        toInteger(account.InvoiceDateDayOfMonth__c)
      );
    }
    if (method == METHOD_DAY_OFFSET) {
      return anchorDate.addDays(toInteger(account.InvoiceDateDayOffset__c));
    }
    throw new ScheduleException('請求日の計算方式が不正です。');
  }

  static Date calculatePaymentScheduledDate(
    BillingAccount__c account,
    Date invoiceDate
  ) {
    String method = account.PaymentTermMethod__c;
    if (method == METHOD_MONTH_OFFSET) {
      return dateInOffsetMonth(
        invoiceDate,
        toInteger(account.PaymentTermMonthOffset__c),
        account.PaymentTermDayKind__c,
        toInteger(account.PaymentTermDayOfMonth__c)
      );
    }
    if (method == METHOD_DAY_OFFSET) {
      return invoiceDate.addDays(toInteger(account.PaymentTermDayOffset__c));
    }
    throw new ScheduleException('支払条件の計算方式が不正です。');
  }

  static Date firstOnOrAfter(Date anchorDate, String dayKind, Integer dayOfMonth) {
    Date sameMonth = dateInMonth(anchorDate.year(), anchorDate.month(), dayKind, dayOfMonth);
    if (sameMonth >= anchorDate) {
      return sameMonth;
    }
    Date nextMonth = Date.newInstance(anchorDate.year(), anchorDate.month(), 1).addMonths(1);
    return dateInMonth(nextMonth.year(), nextMonth.month(), dayKind, dayOfMonth);
  }

  static Date dateInOffsetMonth(
    Date baseDate,
    Integer monthOffset,
    String dayKind,
    Integer dayOfMonth
  ) {
    Date shifted = Date.newInstance(baseDate.year(), baseDate.month(), 1).addMonths(monthOffset);
    return dateInMonth(shifted.year(), shifted.month(), dayKind, dayOfMonth);
  }

  static Date dateInMonth(
    Integer year,
    Integer month,
    String dayKind,
    Integer dayOfMonth
  ) {
    if (dayKind == DAY_KIND_MONTH_END) {
      return Date.newInstance(year, month, Date.daysInMonth(year, month));
    }
    return Date.newInstance(year, month, dayOfMonth);
  }

  static Date applyAdjust(Date value, String adjust) {
    if (value == null || adjust == ADJUST_NONE) {
      return value;
    }
    Id businessHoursId = defaultBusinessHoursId();
    if (businessHoursId == null) {
      throw new ScheduleException('営業日補正には組織の既定営業時間が必要です。');
    }
    Datetime midday = Datetime.newInstance(value, Time.newInstance(12, 0, 0, 0));
    if (BusinessHours.isWithin(businessHoursId, midday)) {
      return value;
    }
    if (adjust == ADJUST_NEXT) {
      return BusinessHours.nextStartDate(businessHoursId, midday).date();
    }
    if (adjust == ADJUST_PREVIOUS) {
      Date cursor = value.addDays(-1);
      for (Integer i = 0; i < 366; i++) {
        Datetime cursorMidday = Datetime.newInstance(
          cursor,
          Time.newInstance(12, 0, 0, 0)
        );
        if (BusinessHours.isWithin(businessHoursId, cursorMidday)) {
          return cursor;
        }
        cursor = cursor.addDays(-1);
      }
      throw new ScheduleException('前営業日を決定できません。');
    }
    throw new ScheduleException('補正が不正です。');
  }

  static Id defaultBusinessHoursId() {
    List<BusinessHours> rows = [
      SELECT Id
      FROM BusinessHours
      WHERE IsDefault = TRUE
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0].Id;
  }

  static void assertDayKindRequired(String label, String dayKind, Integer day) {
    if (dayKind == DAY_KIND_DAY) {
      assertIntegerInRange(label + 'の指定日', day, 1, 28, true);
      return;
    }
    if (dayKind == DAY_KIND_MONTH_END) {
      if (day != null) {
        throw new ScheduleException(label + 'の月末では指定日を空にしてください。');
      }
      return;
    }
    throw new ScheduleException(label + 'の日種別が不正です。');
  }

  static void assertBlank(
    String label,
    String dayKind,
    Integer day,
    Integer monthOffset,
    Integer dayOffset,
    Boolean blankDayKind,
    Boolean blankDay,
    Boolean blankMonthOffset,
    Boolean blankDayOffset
  ) {
    if (blankDayKind && String.isNotBlank(dayKind)) {
      throw new ScheduleException(label + 'で日種別は空にしてください。');
    }
    if (blankDay && day != null) {
      throw new ScheduleException(label + 'で指定日は空にしてください。');
    }
    if (blankMonthOffset && monthOffset != null) {
      throw new ScheduleException(label + 'で月数は空にしてください。');
    }
    if (blankDayOffset && dayOffset != null) {
      throw new ScheduleException(label + 'で日数は空にしてください。');
    }
  }

  static void assertIntegerInRange(
    String label,
    Integer value,
    Integer minValue,
    Integer maxValue,
    Boolean required
  ) {
    if (value == null) {
      if (required) {
        throw new ScheduleException(label + 'は必須です。');
      }
      return;
    }
    if (value < minValue || value > maxValue) {
      throw new ScheduleException(label + 'が範囲外です。');
    }
  }

  static Boolean isInvoiceDateAdjust(String adjust) {
    return adjust == ADJUST_NONE ||
      adjust == ADJUST_PREVIOUS ||
      adjust == ADJUST_NEXT;
  }

  static Integer toInteger(Decimal value) {
    return value == null ? null : value.intValue();
  }
}
