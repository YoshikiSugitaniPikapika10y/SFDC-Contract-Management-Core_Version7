@IsTest
private class GlAccountingPolicyServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void requireOrgPolicy_rejectsWhenMissing() {
    Boolean thrown = false;
    try {
      GlAccountingPolicyService.requireOrgPolicy();
    } catch (Exception ex) {
      thrown = true;
      System.assert(
        ex.getMessage().contains('Accounting会計方針がありません'),
        'Accounting 第3.1節: 組織内1件の会計方針が正本'
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void freezeOnFirstConfirm_rejectsWhenMissing() {
    Boolean thrown = false;
    try {
      GlAccountingPolicyService.freezeOnFirstConfirm();
    } catch (Exception ex) {
      thrown = true;
      System.assert(
        ex.getMessage().contains('Accounting会計方針がありません'),
        'Core 第1.1.10節 / Accounting 第3.1節: 方針0件をOrgDefaultで埋めない'
      );
    }
    System.assertEquals(true, thrown);
    System.assertEquals(
      0,
      [SELECT COUNT() FROM GlAccountingPolicy__c],
      'Core 第1.1.10節: 空の方針を推測して作らない'
    );
  }

  @IsTest
  static void freezeOnFirstConfirm_setsFrozenAt() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      GlAccountingPolicy__c frozen = GlAccountingPolicyService.freezeOnFirstConfirm();
      System.assertNotEquals(
        null,
        frozen.FrozenAt__c,
        'Accounting 第3.1節: 最初の確定で固定日時を入れる'
      );
    }
  }

  @IsTest
  static void deriveAllowedPatternKeys_rejectsInvalidBasis() {
    GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
    policy.RevenueRecognitionBasis__c = 'Unknown';
    Boolean thrown = false;
    try {
      GlAccountingPolicyService.deriveAllowedPatternKeys(policy);
    } catch (GlAccountingPolicyService.PolicyException ex) {
      thrown = true;
      System.assert(
        ex.getMessage().contains('売上計上方針'),
        'Accounting 第5.7節: 保存・固定・原因操作で方針を検証する'
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void trigger_rejectsInvalidTaxTimingOnInsert() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.TaxRecognitionTiming__c = null;
      Boolean thrown = false;
      try {
        insert policy;
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('税認識方針'),
          'Accounting 第5.7節: 保存時に許可集合を検証する'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void isPolicyLocked_trueWhenConfirmedInvoiceExistsWithoutFrozenAt() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Account account = new Account(Name = 'Policy Lock Acc');
      insert account;
      BillingAccount__c billingAccount = new BillingAccount__c(
        Account__c = account.Id,
        BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        BillingEmailTo__c = 'policy-lock@example.com',
        InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER,
        InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY,
        InvoiceDateDayOfMonth__c = 1,
        InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
        PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET,
        PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END,
        PaymentTermMonthOffset__c = 0,
        PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE
      );
      ContractTestDataFactory.applyRequiredFields(billingAccount);
      insert billingAccount;
      ContractService__c service = new ContractService__c(
        Name = 'Policy Lock Svc',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id,
        TaxPercent__c = 0.1
      );
      insert service;
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Policy Lock Hist',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1
      );
      insert history;
      Invoice__c invoice = new Invoice__c(
        ContractService__c = service.Id,
        ContractHistory__c = history.Id,
        InvoiceDate__c = Date.newInstance(2026, 6, 1),
        Amount__c = 1000,
        TaxAmount__c = 0,
        BillingAccountSnapShot__c = billingAccount.Id,
        InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_DRAFT
      );
      insert invoice;
      InvoiceTransactionStatusService.applyConfirmed(
        new List<Invoice__c>{ invoice },
        Date.newInstance(2026, 6, 1)
      );
      Boolean previousStatus = InvoiceTransactionStatusService.allowStatusWrite;
      Boolean previousLock = InvoiceLockUtil.allowLockedStatusWrite;
      InvoiceTransactionStatusService.allowStatusWrite = true;
      InvoiceLockUtil.allowLockedStatusWrite = true;
      try {
        update invoice;
      } finally {
        InvoiceTransactionStatusService.allowStatusWrite = previousStatus;
        InvoiceLockUtil.allowLockedStatusWrite = previousLock;
      }
      // FrozenAt を外して「確定あり・未固定」の経路を再現する
      Boolean previous = GlAccountingPolicyService.allowFreezeWrite;
      GlAccountingPolicyService.allowFreezeWrite = true;
      try {
        GlAccountingPolicy__c policy = GlAccountingPolicyService.requireOrgPolicy();
        policy.FrozenAt__c = null;
        policy.FrozenBy__c = null;
        update policy;
      } finally {
        GlAccountingPolicyService.allowFreezeWrite = previous;
      }
      GlAccountingPolicy__c unlocked = GlAccountingPolicyService.requireOrgPolicy();
      System.assertEquals(
        null,
        unlocked.FrozenAt__c,
        '前提: FrozenAt が空'
      );
      System.assertEquals(
        true,
        GlAccountingPolicyService.isPolicyLocked(unlocked),
        'Accounting 第3.1節 / Core 第11.8節: Confirmed があれば FrozenAt 空でもロック'
      );
      Boolean thrown = false;
      try {
        unlocked.AccountingEnabled__c = true;
        update unlocked;
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('確定済みまたは取消済み'),
          'Accounting 第3.1節 / Core 第11.8節: FrozenAt だけでなく確定／取消で拒否'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void rewriteRecognitionBucketCounts_appliesCalendarMonth() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.MonthlyBucketMethod__c = 'Auto';
      insert policy;

      Account account = ContractTestDataFactory.insertAccount('Bucket Rewrite Acct');
      BillingAccount__c billingAccount = new BillingAccount__c(
        Account__c = account.Id,
        BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        BillingEmailTo__c = 'to@example.com',
        InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER,
        InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY,
        InvoiceDateDayOfMonth__c = 1,
        InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
        PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET,
        PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END,
        PaymentTermMonthOffset__c = 0,
        PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE
      );
      ContractTestDataFactory.applyRequiredFields(billingAccount);
      insert billingAccount;
      ContractService__c service = new ContractService__c(
        Name = 'Bucket Rewrite Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id,
        TaxPercent__c = 0.1
      );
      insert service;
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Bucket Rewrite History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1
      );
      insert history;
      Invoice__c invoice = new Invoice__c(
        ContractService__c = service.Id,
        ContractHistory__c = history.Id,
        InvoiceDate__c = Date.newInstance(2025, 4, 15),
        Amount__c = 1000
      );
      insert invoice;
      InvoiceLine__c line = new InvoiceLine__c(
        Invoice__c = invoice.Id,
        Amount__c = 1000,
        RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_OVER_TIME,
        ServicePeriodStartDate__c = Date.newInstance(2025, 4, 15),
        ServicePeriodEndDate__c = Date.newInstance(2026, 4, 14)
      );
      insert line;
      line = [
        SELECT RecognitionBucketCount__c
        FROM InvoiceLine__c
        WHERE Id = :line.Id
      ];
      System.assertEquals(
        12,
        line.RecognitionBucketCount__c,
        'Accounting 第3.3節: Auto の 4/15～翌4/14 は12'
      );

      policy.MonthlyBucketMethod__c = 'CalendarMonth';
      update policy;
      Test.startTest();
      GlAccountingPolicyService.rewriteRecognitionBucketCounts();
      Test.stopTest();
      line = [
        SELECT RecognitionBucketCount__c
        FROM InvoiceLine__c
        WHERE Id = :line.Id
      ];
      System.assertEquals(
        13,
        line.RecognitionBucketCount__c,
        'Accounting 第3.2節: 月次方式変更で組織内の請求明細を書き直す'
      );
    }
  }
}
