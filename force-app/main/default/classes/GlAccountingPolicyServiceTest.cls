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
  static void deriveAllowedPatternKeys_cashAtInvoice_allowsTaxAtInvoice() {
    GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
    policy.RevenueRecognitionBasis__c = 'CashBasis';
    policy.TaxRecognitionTiming__c = 'AtInvoice';
    Set<String> keys = GlAccountingPolicyService.deriveAllowedPatternKeys(policy);
    System.assertEquals(
      true,
      keys.contains('BILLING_TAX_AT_INVOICE'),
      'Accounting 第5.7節: 入金連動前受かつ請求時税は請求時税パターンを許可する'
    );
    System.assertEquals(
      true,
      keys.contains('CASH_BASIS_INVOICE_BODY_CTA_TRANSFER'),
      'Accounting 第5.7節: 入金連動前受の本体は前受振替'
    );
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
      Invoice__c invoice = insertDraftInvoiceOnOrdered(
        'Policy Lock',
        Date.newInstance(2026, 6, 1),
        Date.newInstance(2027, 5, 31)
      );
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

      Invoice__c invoice = insertDraftInvoiceOnOrdered(
        'Bucket Rewrite',
        Date.newInstance(2025, 4, 15),
        Date.newInstance(2026, 4, 14)
      );
      InvoiceLine__c line = new InvoiceLine__c(
        Invoice__c = invoice.Id,
        ProductName__c = 'Bucket Rewrite Line',
        Amount__c = 1000,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_OVER_TIME,
        ServicePeriodStartDate__c = Date.newInstance(2025, 4, 15),
        ServicePeriodEndDate__c = Date.newInstance(2026, 4, 14)
      );
      ContractTestDataFactory.applyRequiredFields(line);
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
      GlAccountingPolicyService.clearCachedOrgPolicy();
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

  @IsTest
  static void freezeOnFirstConfirm_alreadyFrozen_keepsFrozenAt() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      GlAccountingPolicy__c first = GlAccountingPolicyService.freezeOnFirstConfirm();
      Datetime frozenAt = first.FrozenAt__c;
      Id frozenBy = first.FrozenBy__c;
      GlAccountingPolicy__c second = GlAccountingPolicyService.freezeOnFirstConfirm();
      System.assertEquals(
        frozenAt,
        second.FrozenAt__c,
        'Accounting 第3.1節: 既に固定済みなら固定日時を書き直さない'
      );
      System.assertEquals(frozenBy, second.FrozenBy__c);
    }
  }

  @IsTest
  static void deriveAllowedPatternKeys_rejectsNullAndInvalidTax() {
    Boolean missing = false;
    try {
      GlAccountingPolicyService.deriveAllowedPatternKeys(null);
    } catch (GlAccountingPolicyService.PolicyException ex) {
      missing = true;
      System.assertEquals(
        'Accounting会計方針がありません。',
        ex.getMessage(),
        'Accounting 第3.1節: 方針が無ければ許可集合を作らない'
      );
    }
    System.assertEquals(true, missing);

    GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
    policy.TaxRecognitionTiming__c = 'Unknown';
    Boolean invalidTax = false;
    try {
      GlAccountingPolicyService.deriveAllowedPatternKeys(policy);
    } catch (GlAccountingPolicyService.PolicyException ex) {
      invalidTax = true;
      System.assertEquals(
        '税認識方針が不正です。',
        ex.getMessage(),
        'Accounting 第5.7節: 税認識方針が許可集合の正本'
      );
    }
    System.assertEquals(true, invalidTax);
  }

  @IsTest
  static void deriveAllowedPatternKeys_billingAndCashAtRecognition() {
    GlAccountingPolicy__c billing = GlAccountingPolicyService.newOrgDefault();
    billing.RevenueRecognitionBasis__c = 'BillingBasis';
    billing.TaxRecognitionTiming__c = 'AtRecognition';
    Set<String> billingKeys = GlAccountingPolicyService.deriveAllowedPatternKeys(
      billing
    );
    System.assertEquals(
      true,
      billingKeys.contains('BILLING_BASIS_INVOICE_TAX_DEFERRED'),
      'Accounting 第5.7節: 請求基準かつ売上計上時税は繰延税を許可する'
    );
    System.assertEquals(
      false,
      billingKeys.contains('BILLING_TAX_AT_INVOICE'),
      'Accounting 第5.7節: 売上計上時税に請求時税パターンを混ぜない'
    );

    GlAccountingPolicy__c cash = GlAccountingPolicyService.newOrgDefault();
    cash.RevenueRecognitionBasis__c = 'CashBasis';
    cash.TaxRecognitionTiming__c = 'AtRecognition';
    Set<String> cashKeys = GlAccountingPolicyService.deriveAllowedPatternKeys(cash);
    System.assertEquals(
      true,
      cashKeys.contains('CASH_BASIS_INVOICE_TAX_CTA_TRANSFER'),
      'Accounting 第5.7節: 入金連動前受かつ売上計上時税は税の前受振替を許可する'
    );
    System.assertEquals(
      true,
      cashKeys.contains('CASH_BASIS_REVENUE_TAX')
    );
  }

  @IsTest
  static void requireOrgPolicy_returnsCachedOrgDefault() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      GlAccountingPolicy__c first = GlAccountingPolicyService.requireOrgPolicy();
      GlAccountingPolicy__c second = GlAccountingPolicyService.requireOrgPolicy();
      System.assertEquals(
        first.Id,
        second.Id,
        'Accounting 第3.1節: 組織内1件の会計方針を正本として返す'
      );
      System.assertEquals(
        GlAccountingPolicyService.ORG_DEFAULT_NAME,
        first.Name
      );
      System.assertEquals(false, first.AccountingEnabled__c);
      GlAccountingPolicyService.clearCachedOrgPolicy();
      GlAccountingPolicy__c afterClear = GlAccountingPolicyService.requireOrgPolicy();
      System.assertEquals(first.Id, afterClear.Id);
    }
  }

  private static Invoice__c insertDraftInvoiceOnOrdered(
    String prefix,
    Date termStart,
    Date termEnd
  ) {
    Account account = ContractTestDataFactory.insertAccount(prefix + ' Acc');
    ContractService__c service = ContractTestDataFactory.insertContractService(
      account.Id,
      prefix + ' Svc'
    );
    ContractHistory__c history = new ContractHistory__c(
      Name = prefix + ' Hist',
      ContractService__c = service.Id,
      Type__c = 'New',
      historystatus__c = 'Estimate',
      Version__c = 1,
      CurrentTermStartDate__c = termStart,
      CurrentTermEndDate__c = termEnd,
      EffectiveDate__c = termStart
    );
    ContractTestDataFactory.applyEstimateOrderedOpportunity(history, account.Id);
    insert history;
    Product2 product = ContractTestDataFactory.buildProduct(prefix + ' Product');
    product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
    ContractTestDataFactory.insertProduct(product);
    ContractProduct__c contractProduct = new ContractProduct__c(
      ContractHistory__c = history.Id,
      Account__c = account.Id,
      Product__c = product.Id,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      Amount__c = 1000,
      StartDate__c = termStart,
      Enddate__c = termEnd,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
      Type__c = 'New',
      RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_OVER_TIME
    );
    ContractTestDataFactory.applyRequiredFields(contractProduct);
    contractProduct.Amount__c = 1000;
    insert contractProduct;
    history.historystatus__c = 'Ordered';
    update history;
    Invoice__c invoice = new Invoice__c(
      ContractService__c = service.Id,
      ContractHistory__c = history.Id,
      InvoiceDate__c = termStart,
      Amount__c = 1000,
      TaxAmount__c = 0,
      BillingAccountSnapShot__c = service.BiilingAcccount__c
    );
    ContractTestDataFactory.applyInvoiceInsertSeedStatuses(invoice);
    insert invoice;
    return invoice;
  }
}
