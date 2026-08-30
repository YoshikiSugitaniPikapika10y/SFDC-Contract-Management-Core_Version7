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
      System.assert(
        ex.getMessage().contains('入金予定日が請求日より前'),
        ex.getMessage()
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
    }
    System.assertEquals(
      true,
      rejected,
      'Core 第7.2節: 入らない項目は空にする。入っている場合は保存時に拒否する'
    );
  }
}
