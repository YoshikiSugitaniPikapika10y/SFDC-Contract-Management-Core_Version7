@IsTest
private class AccountingCauseLockServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void lockInvoice_rejectsNull() {
    Boolean thrown = false;
    try {
      AccountingCauseLockService.lockInvoice(null);
    } catch (Exception ex) {
      thrown = true;
      System.assert(
        ex.getMessage().contains('請求が指定されていません'),
        'Accounting 第8.2節: 対象請求書が無ければパイプラインを始めない'
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void lockInvoice_returnsTargetInvoice() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = insertDraftInvoice();
      Invoice__c locked = AccountingCauseLockService.lockInvoice(invoice.Id);
      System.assertEquals(
        invoice.Id,
        locked.Id,
        'Accounting 第8.2節: 対象請求書を行ロックする'
      );
    }
  }

  @IsTest
  static void issueOperationKey_returnsDistinctKeys() {
    String first = AccountingCauseLockService.issueOperationKey();
    String second = AccountingCauseLockService.issueOperationKey();
    System.assertEquals(
      true,
      String.isNotBlank(first),
      'Core 第7.9.7節: サーバが業務操作キーを発行する'
    );
    System.assertEquals(
      false,
      first == second,
      'Core 第7.9.7節: 応答前の連打は別キーである'
    );
  }

  @IsTest
  static void resolveInvoiceOperationDatetime_includesJournal() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = insertDraftInvoice();
      Datetime before = AccountingCauseLockService.resolveInvoiceOperationDatetime(
        invoice.Id
      );
      GlAccount__c debit = new GlAccount__c(
        Name = 'Lock Debit',
        AccountType__c = 'Asset',
        IsActive__c = true
      );
      GlAccount__c credit = new GlAccount__c(
        Name = 'Lock Credit',
        AccountType__c = 'Liability',
        IsActive__c = true
      );
      insert new List<GlAccount__c>{ debit, credit };
      insert new GlJournal__c(
        Invoice__c = invoice.Id,
        Amount__c = 1,
        IdempotencyKey__c = AccountingDiffService.hashKey(
          new List<String>{ 'LockJournal', String.valueOf(invoice.Id) }
        ),
        DebitSlotKey__c = 'Cash',
        CreditSlotKey__c = 'UnappliedCash',
        DebitAccount__c = debit.Id,
        CreditAccount__c = credit.Id,
        PostingDate__c = Date.newInstance(2026, 6, 1),
        TransactionStatus__c = 'Active'
      );
      Datetime afterJournal = AccountingCauseLockService.resolveInvoiceOperationDatetime(
        invoice.Id
      );
      System.assertEquals(
        true,
        afterJournal.getTime() >= before.getTime(),
        'Core 第7.9.7節: 版は対象請求と配下の仕訳を含む'
      );
    }
  }

  private static Invoice__c insertDraftInvoice() {
    Account account = ContractTestDataFactory.insertAccount(
      'Lock ' + String.valueOf(Crypto.getRandomInteger())
    );
    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = account.Id,
      BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
      BillingEmailTo__c = 'lock@example.com',
      InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER,
      InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY,
      InvoiceDateDayOfMonth__c = 1,
      InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
      PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET,
      PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END,
      PaymentTermMonthOffset__c = 0,
      PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE);
    ContractTestDataFactory.applyRequiredFields(billingAccount);
    insert billingAccount;
    Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
      account.Id,
      'Lock Opp'
    );
    ContractService__c service = new ContractService__c(
      Name = 'Lock Service',
      Account__c = account.Id,
      BiilingAcccount__c = billingAccount.Id,
      TaxPercent__c = 0.1
    );
    insert service;
    ContractHistory__c history = new ContractHistory__c(
      Name = 'Lock History',
      ContractService__c = service.Id,
      Opportunity__c = opportunity.Id,
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
      TaxAmount__c = 100,
      TaxInclusiveAmount__c = 1100,
      BillingAccountSnapShot__c = billingAccount.Id,
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_DRAFT
    );
    insert invoice;
    return invoice;
  }
}
