@IsTest
private class BillingScheduleServiceTest {
  @IsTest
  static void computeInvoiceDate_sameDayUsesAnchor() {
    BillingAccount__c account = new BillingAccount__c();
    ContractTestDataFactory.applySameDayBilling(account);
    Date anchor = Date.newInstance(2026, 1, 31);
    System.assertEquals(
      anchor,
      BillingScheduleService.computeInvoiceDateFromAnchor(account, anchor),
      'Core 第7.2節: 基準日と同日は請求基準日をそのまま請求日とする'
    );
  }

  @IsTest
  static void computeInvoiceDate_onOrAfterUsesNextMonthWhenPast() {
    BillingAccount__c account = new BillingAccount__c();
    ContractTestDataFactory.applyOnOrAfterBillingDay(account, 15);
    Date invoiceDate = BillingScheduleService.computeInvoiceDateFromAnchor(
      account,
      Date.newInstance(2026, 1, 16)
    );
    System.assertEquals(
      Date.newInstance(2026, 2, 15),
      invoiceDate,
      'Core 第7.2節: 基準日以後で最初に到来する指定日'
    );
  }

  @IsTest
  static void computePaymentScheduledDate_matchesDateSpecExamples() {
    Date invoiceDate = Date.newInstance(2026, 6, 1);
    BillingAccount__c monthEndSame = new BillingAccount__c();
    ContractTestDataFactory.applyPaymentMonthEnd(monthEndSame, 0);
    System.assertEquals(
      Date.newInstance(2026, 6, 30),
      BillingScheduleService.computePaymentScheduledDate(
        monthEndSame,
        invoiceDate
      ),
      '日付仕様 第5章: 請求月から0か月後の月末'
    );

    BillingAccount__c nextMonth15 = new BillingAccount__c();
    ContractTestDataFactory.applyPaymentMonthDay(nextMonth15, 1, 15);
    System.assertEquals(
      Date.newInstance(2026, 7, 15),
      BillingScheduleService.computePaymentScheduledDate(
        nextMonth15,
        invoiceDate
      ),
      '日付仕様 第5章: 1か月後の15日'
    );

    BillingAccount__c nextMonthEnd = new BillingAccount__c();
    ContractTestDataFactory.applyPaymentMonthEnd(nextMonthEnd, 1);
    System.assertEquals(
      Date.newInstance(2026, 7, 31),
      BillingScheduleService.computePaymentScheduledDate(
        nextMonthEnd,
        invoiceDate
      ),
      '日付仕様 第5章: 1か月後の月末'
    );

    BillingAccount__c dayOffset = new BillingAccount__c();
    dayOffset.PaymentTermMethod__c = BillingScheduleService.METHOD_DAY_OFFSET;
    dayOffset.PaymentTermDayOffset__c = 30;
    dayOffset.PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE;
    System.assertEquals(
      Date.newInstance(2026, 7, 1),
      BillingScheduleService.computePaymentScheduledDate(dayOffset, invoiceDate),
      '日付仕様 第5章: 請求日から30日後'
    );
  }

  @IsTest
  static void computePaymentScheduledDate_rejectsBeforeInvoiceDate() {
    BillingAccount__c account = new BillingAccount__c();
    ContractTestDataFactory.applyPaymentMonthDay(account, 0, 1);
    Boolean rejected = false;
    try {
      BillingScheduleService.computePaymentScheduledDate(
        account,
        Date.newInstance(2026, 1, 31)
      );
    } catch (BillingScheduleService.ScheduleException ex) {
      rejected = true;
      System.assertEquals(
        '入金予定日が請求日より前になる設定は使えません。',
        ex.getMessage(),
        'Core 第7.5節: 入金予定日が請求日より前になる設定は拒否する'
      );
    }
    System.assertEquals(
      true,
      rejected,
      'Core 第7.5節: 入金予定日が請求日より前になる設定は拒否する'
    );
  }

  @IsTest
  static void assertSchedule_rejectsExtraFieldsForSameDay() {
    BillingAccount__c account = new BillingAccount__c();
    ContractTestDataFactory.applySameDayBilling(account);
    account.InvoiceDateDayOfMonth__c = 15;
    Boolean rejected = false;
    try {
      BillingScheduleService.assertSchedule(account);
    } catch (BillingScheduleService.ScheduleException ex) {
      rejected = true;
      System.assertEquals(
        '請求日ルールで指定日は空にしてください。',
        ex.getMessage(),
        'Core 第7.2節: 入らない項目は空にする。入っている場合は保存時に拒否する'
      );
    }
    System.assertEquals(
      true,
      rejected,
      'Core 第7.2節: 入らない項目は空にする。入っている場合は保存時に拒否する'
    );
  }

  @IsTest
  static void assertSchedule_rejectsExtraPaymentFieldsForDayOffset() {
    BillingAccount__c account = new BillingAccount__c();
    ContractTestDataFactory.applySameDayBilling(account);
    account.PaymentTermMethod__c = BillingScheduleService.METHOD_DAY_OFFSET;
    account.PaymentTermDayOffset__c = 0;
    account.PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE;
    account.PaymentTermMonthOffset__c = 1;
    Boolean rejected = false;
    try {
      BillingScheduleService.assertSchedule(account);
    } catch (BillingScheduleService.ScheduleException ex) {
      rejected = true;
      System.assertEquals(
        '支払条件で月数は空にしてください。',
        ex.getMessage(),
        'Core 第7.5節: 入らない項目は空にする。入っている場合は保存時に拒否する'
      );
    }
    System.assertEquals(
      true,
      rejected,
      'Core 第7.5節: 入らない項目は空にする。入っている場合は保存時に拒否する'
    );
  }

  @IsTest
  static void computeInvoiceDate_onOrAfterSameDayWhenAnchorMatches() {
    BillingAccount__c account = new BillingAccount__c();
    ContractTestDataFactory.applyOnOrAfterBillingDay(account, 15);
    System.assertEquals(
      Date.newInstance(2026, 1, 15),
      BillingScheduleService.computeInvoiceDateFromAnchor(
        account,
        Date.newInstance(2026, 1, 15)
      ),
      'Core 第7.2節: 請求基準日自身が該当すれば同日とする'
    );
  }

  @IsTest
  static void computeInvoiceDate_onOrAfterMonthEnd() {
    BillingAccount__c account = new BillingAccount__c();
    account.InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER;
    account.InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END;
    account.InvoiceDateDayOfMonth__c = null;
    account.InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE;
    System.assertEquals(
      Date.newInstance(2026, 1, 31),
      BillingScheduleService.computeInvoiceDateFromAnchor(
        account,
        Date.newInstance(2026, 1, 16)
      ),
      'Core 第7.2節: 基準日以後で最初に到来する月末'
    );
  }

  @IsTest
  static void computeInvoiceDate_monthOffsetAndDayOffset() {
    BillingAccount__c monthOffset = new BillingAccount__c();
    monthOffset.InvoiceDateMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET;
    monthOffset.InvoiceDateMonthOffset__c = 1;
    monthOffset.InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY;
    monthOffset.InvoiceDateDayOfMonth__c = 10;
    monthOffset.InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE;
    System.assertEquals(
      Date.newInstance(2026, 2, 10),
      BillingScheduleService.computeInvoiceDateFromAnchor(
        monthOffset,
        Date.newInstance(2026, 1, 31)
      ),
      'Core 第7.2節: 基準月を0として指定月数前後した月の指定日'
    );

    BillingAccount__c dayOffset = new BillingAccount__c();
    dayOffset.InvoiceDateMethod__c = BillingScheduleService.METHOD_DAY_OFFSET;
    dayOffset.InvoiceDateDayOffset__c = 1;
    dayOffset.InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE;
    System.assertEquals(
      Date.newInstance(2026, 2, 1),
      BillingScheduleService.computeInvoiceDate(
        dayOffset,
        Date.newInstance(2026, 1, 31)
      ),
      'Core 第7.2節: 基準日から指定日数を加減する'
    );
  }

  @IsTest
  static void computePaymentScheduledDate_zeroDayOffsetIsSameDay() {
    BillingAccount__c account = new BillingAccount__c();
    account.PaymentTermMethod__c = BillingScheduleService.METHOD_DAY_OFFSET;
    account.PaymentTermDayOffset__c = 0;
    account.PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE;
    Date invoiceDate = Date.newInstance(2026, 6, 1);
    System.assertEquals(
      invoiceDate,
      BillingScheduleService.computePaymentScheduledDate(account, invoiceDate),
      'Core 第7.5節: 0日は即日払いを表す'
    );
  }

  @IsTest
  static void applySnapshots_copiesScheduleFieldsWhenBlank() {
    BillingAccount__c account = new BillingAccount__c();
    ContractTestDataFactory.applySameDayBilling(account);
    ContractTestDataFactory.applyPaymentMonthEnd(account, 0);
    Invoice__c invoice = new Invoice__c();
    BillingScheduleService.applySnapshots(invoice, account);
    System.assertEquals(
      BillingScheduleService.METHOD_SAME_DAY,
      invoice.InvoiceDateMethodSnapShot__c,
      'Core 第7.2節: 生成時に請求日ルールをスナップショットする'
    );
    System.assertEquals(
      BillingScheduleService.METHOD_MONTH_OFFSET,
      invoice.PaymentTermMethodSnapShot__c,
      'Core 第7.5節: 生成時に支払条件をスナップショットする'
    );
    System.assertEquals(
      BillingScheduleService.DAY_KIND_MONTH_END,
      invoice.PaymentTermDayKindSnapShot__c
    );
    System.assertEquals(0, invoice.PaymentTermMonthOffsetSnapShot__c);
  }

  @IsTest
  static void assertSchedule_rejectsMonthEndWithSpecifiedDay() {
    BillingAccount__c account = new BillingAccount__c();
    account.InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER;
    account.InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END;
    account.InvoiceDateDayOfMonth__c = 15;
    account.InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE;
    ContractTestDataFactory.applyPaymentMonthEnd(account, 0);
    Boolean rejected = false;
    try {
      BillingScheduleService.assertSchedule(account);
    } catch (BillingScheduleService.ScheduleException ex) {
      rejected = true;
      System.assertEquals(
        '請求日ルールの月末では指定日を空にしてください。',
        ex.getMessage(),
        'Core 第7.2節: MonthEnd のときは指定日を空にする'
      );
    }
    System.assertEquals(
      true,
      rejected,
      'Core 第7.2節: MonthEnd のときは指定日を空にする'
    );
  }

  @IsTest
  static void assertSchedule_rejectsNullAccount() {
    Boolean rejected = false;
    try {
      BillingScheduleService.assertSchedule(null);
    } catch (BillingScheduleService.ScheduleException ex) {
      rejected = true;
      System.assertEquals(
        '請求アカウントが指定されていません。',
        ex.getMessage(),
        'Core 第7.2節: 請求アカウント無しでは請求日も支払条件も計算しない'
      );
    }
    System.assertEquals(true, rejected);
  }

  @IsTest
  static void computeInvoiceDate_fiveArgUsesProductStartWhenPeriodStartBlank() {
    BillingAccount__c account = new BillingAccount__c();
    ContractTestDataFactory.applyOnOrAfterBillingDay(account, 1);
    Date invoiceDate = BillingScheduleService.computeInvoiceDate(
      account,
      null,
      Date.newInstance(2026, 6, 30),
      Date.newInstance(2026, 6, 1),
      Date.newInstance(2026, 6, 30)
    );
    System.assertEquals(
      Date.newInstance(2026, 6, 1),
      invoiceDate,
      'Core 第7.2節: 期間開始が空なら見積商品開始日を基準にする。推測で埋めない'
    );
  }

  @IsTest
  static void computeInvoiceDateFromAnchor_nullAnchorReturnsNull() {
    BillingAccount__c account = new BillingAccount__c();
    ContractTestDataFactory.applySameDayBilling(account);
    System.assertEquals(
      null,
      BillingScheduleService.computeInvoiceDateFromAnchor(account, null),
      'Core 第7.2節: 基準日が空なら請求日を作らない'
    );
  }

  @IsTest
  static void computePaymentScheduledDate_nullInvoiceDateReturnsNull() {
    BillingAccount__c account = new BillingAccount__c();
    ContractTestDataFactory.applyPaymentMonthEnd(account, 0);
    System.assertEquals(
      null,
      BillingScheduleService.computePaymentScheduledDate(account, null),
      'Core 第7.5節: 請求日が空なら入金予定日を推測しない'
    );
  }

  @IsTest
  static void computePaymentScheduledDate_usesCalendarMonthNotCycle() {
    BillingAccount__c account = new BillingAccount__c();
    ContractTestDataFactory.applyPaymentMonthDay(account, 1, 15);
    System.assertEquals(
      Date.newInstance(2026, 2, 15),
      BillingScheduleService.computePaymentScheduledDate(
        account,
        Date.newInstance(2026, 1, 31)
      ),
      '日付仕様 第5章: 支払条件は暦月。1/31基準の1か月後の15日は2/15でありサイクル終了（2/27）ではない'
    );
  }

  @IsTest
  static void applySnapshots_copiesBlankInvoiceFieldsFromAccount() {
    BillingAccount__c account = new BillingAccount__c();
    ContractTestDataFactory.applyOnOrAfterBillingDay(account, 25);
    ContractTestDataFactory.applyPaymentMonthEnd(account, 0);
    Invoice__c invoice = new Invoice__c();
    BillingScheduleService.applySnapshots(invoice, account);
    System.assertEquals(
      account.InvoiceDateMethod__c,
      invoice.InvoiceDateMethodSnapShot__c,
      'Core 第7.2節: 生成時だけ請求日ルールをスナップショットする'
    );
    System.assertEquals(
      account.PaymentTermMethod__c,
      invoice.PaymentTermMethodSnapShot__c,
      'Core 第7.5節: 生成時だけ支払条件をスナップショットする'
    );
  }

  @IsTest
  static void applySnapshots_nullArgumentsDoNotThrow() {
    BillingScheduleService.applySnapshots(null, new BillingAccount__c());
    BillingScheduleService.applySnapshots(new Invoice__c(), null);
  }
}
