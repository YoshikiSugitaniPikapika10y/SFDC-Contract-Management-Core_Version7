@IsTest
private class ContractCrossQueryServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
    ContractTestDataFactory.ensureOrgDocumentSetting();
    insert GlAccountingPolicyService.newOrgDefault();
  }

  @IsTest
  static void defaultDates_matchCrossSectionFive() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Date today = ContractCrossQueryService.organizationToday();
      ContractCrossQueryService.DateRange estimate = ContractCrossQueryService.defaultEstimateCloseDates();
      System.assertEquals(
        today.addDays(-90),
        estimate.dateFrom,
        '共通基盤契約横断取得: 見積の既定 FROM は今日の90日前'
      );
      System.assertEquals(
        today.toStartOfMonth().addMonths(1).addDays(-1),
        estimate.dateTo,
        '共通基盤契約横断取得: 見積の既定 TO は今月末'
      );
      ContractCrossQueryService.DateRange journal = ContractCrossQueryService.defaultJournalPostingDates();
      System.assertEquals(
        today.toStartOfMonth().addMonths(-1),
        journal.dateFrom,
        '共通基盤契約横断取得: 仕訳の既定は先月の1日'
      );
      System.assertEquals(
        today.toStartOfMonth().addDays(-1),
        journal.dateTo,
        '共通基盤契約横断取得: 仕訳の既定は先月の末日'
      );
    }
  }

  @IsTest
  static void queryEstimates_rejectsBlankCloseDatesAndReturnsEstimateOnly() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Boolean blankThrown = false;
      try {
        ContractCrossQueryService.queryEstimates(null);
      } catch (ContractCrossQueryService.QueryException ex) {
        blankThrown = true;
        System.assertEquals(
          '完了予定日の FROM と TO は空にできません。',
          ex.getMessage(),
          '共通基盤契約横断取得: 見積の完了予定日は空にできない'
        );
      }
      System.assertEquals(true, blankThrown);

      Date today = ContractCrossQueryService.organizationToday();
      HistoryFixture inRange = insertHistory('Estimate', today, 'QEst In');
      insertHistory('Estimate', today.addYears(-1), 'QEst Old');
      insertHistory('Ordered', today, 'QEst Ordered');

      ContractCrossController.EstimateFilterDto filter = new ContractCrossController.EstimateFilterDto();
      ContractCrossQueryService.DateRange range = ContractCrossQueryService.defaultEstimateCloseDates();
      filter.closeDateFrom = range.dateFrom;
      filter.closeDateTo = range.dateTo;
      filter.sent = false;
      filter.issued = false;
      filter.autoRenew = false;
      filter.estimateType = 'New';
      filter.accountId = inRange.opportunity.AccountId;
      filter.serviceId = inRange.history.ContractService__c;
      ContractCrossController.ListResultDto result = ContractCrossQueryService.queryEstimates(
        filter
      );
      System.assertEquals(false, result.truncated);
      System.assertEquals(null, result.truncatedMessage);
      System.assertEquals(1, result.estimates.size());
      System.assertEquals(inRange.history.Id, result.estimates[0].id);
      System.assertEquals(false, result.estimates[0].sent);
      System.assertEquals(false, result.estimates[0].issued);
    }
  }

  @IsTest
  static void queryInvoices_rejectsBlankStatusAndKeepsBlankInvoiceDate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Boolean blankThrown = false;
      try {
        ContractCrossQueryService.queryInvoices(
          new ContractCrossController.InvoiceFilterDto()
        );
      } catch (ContractCrossQueryService.QueryException ex) {
        blankThrown = true;
        System.assertEquals(
          '請求状態は未確定／確定／両方のいずれかです。',
          ex.getMessage(),
          '共通基盤契約横断取得: 請求状態は未指定不可'
        );
      }
      System.assertEquals(true, blankThrown);

      HistoryFixture historyFixture = insertHistory(
        'Ordered',
        ContractCrossQueryService.organizationToday(),
        'QInv Draft'
      );
      Invoice__c draft = new Invoice__c(
        ContractService__c = historyFixture.history.ContractService__c,
        ContractHistory__c = historyFixture.history.Id,
        InvoiceDate__c = null,
        Amount__c = 1000,
        TaxAmount__c = 100,
        BillingAccountSnapShot__c = historyFixture.billingAccount.Id,
        InvoiceTransactionStatus__c = 'Draft'
      );
      ContractTestDataFactory.insertAllowingInvoiceStatus(draft);
      draft = [SELECT Id, Name FROM Invoice__c WHERE Id = :draft.Id];

      ContractCrossController.InvoiceFilterDto filter = new ContractCrossController.InvoiceFilterDto();
      filter.invoiceStatus = ContractCrossQueryService.INVOICE_STATUS_DRAFT;
      filter.invoiceDateFrom = Date.newInstance(2026, 1, 1);
      filter.invoiceDateTo = Date.newInstance(2026, 12, 31);
      filter.invoiceName = draft.Name;
      filter.billingAccountId = historyFixture.billingAccount.Id;
      filter.accountId = historyFixture.opportunity.AccountId;
      filter.sent = false;
      filter.overdue = false;
      ContractCrossController.ListResultDto result = ContractCrossQueryService.queryInvoices(
        filter
      );
      System.assertEquals(1, result.invoices.size());
      System.assertEquals(draft.Id, result.invoices[0].id);
      System.assertEquals(
        null,
        result.invoices[0].invoiceDate,
        '共通基盤契約横断取得: FROM・TOは空の請求日を消さない'
      );

      filter.invoiceStatus = ContractCrossQueryService.INVOICE_STATUS_BOTH;
      filter.issued = false;
      ContractCrossController.ListResultDto unissued = ContractCrossQueryService.queryInvoices(
        filter
      );
      System.assertEquals(true, unissued.invoices.size() >= 1);
    }
  }

  @IsTest
  static void queryJournals_accountingOffAndUnlockedLastMonth() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractCrossController.JournalFilterDto filter = new ContractCrossController.JournalFilterDto();
      ContractCrossQueryService.DateRange range = ContractCrossQueryService.defaultJournalPostingDates();
      filter.postingDateFrom = range.dateFrom;
      filter.postingDateTo = range.dateTo;
      filter.lockState = ContractCrossQueryService.LOCK_UNLOCKED;
      Boolean offThrown = false;
      try {
        ContractCrossQueryService.queryJournals(filter);
      } catch (ContractCrossQueryService.QueryException ex) {
        offThrown = true;
        System.assertEquals(
          'AccountingがOFFのときは仕訳一覧を出せません。',
          ex.getMessage(),
          '共通基盤契約横断取得: Accounting OFFでは仕訳一覧を出さない'
        );
      }
      System.assertEquals(true, offThrown);

      enableAccounting();
      GlAccountingPolicyService.clearCachedOrgPolicy();
      InvoiceFixture invoiceFixture = insertInvoice('Confirmed');
      insertJournal(
        invoiceFixture.invoice.Id,
        false,
        'Active',
        range.dateFrom,
        'QJnl'
      );
      filter.invoiceId = invoiceFixture.invoice.Id;
      filter.billingAccountId = [
          SELECT BillingAccountSnapShot__c
          FROM Invoice__c
          WHERE Id = :invoiceFixture.invoice.Id
        ]
        .BillingAccountSnapShot__c;
      ContractCrossController.ListResultDto result = ContractCrossQueryService.queryJournals(
        filter
      );
      System.assertEquals(1, result.journals.size());
      System.assertEquals(false, result.journals[0].isLocked);
    }
  }

  @IsTest
  static void getEstimateTile_estimateOnlyAndMissingHistory() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Boolean missingThrown = false;
      try {
        ContractCrossQueryService.getEstimateTile(null);
      } catch (ContractCrossQueryService.QueryException ex) {
        missingThrown = true;
        System.assertEquals('契約履歴が指定されていません。', ex.getMessage());
      }
      System.assertEquals(true, missingThrown);

      HistoryFixture estimate = insertHistory(
        'Estimate',
        ContractCrossQueryService.organizationToday(),
        'QTile Est'
      );
      ContractCrossController.EstimateTileDto tile = ContractCrossQueryService.getEstimateTile(
        estimate.history.Id
      );
      System.assertEquals(true, tile.isEstimate);
      System.assertEquals(estimate.history.Name, tile.historyName);

      HistoryFixture ordered = insertHistory(
        'Ordered',
        ContractCrossQueryService.organizationToday(),
        'QTile Ord'
      );
      ContractCrossController.EstimateTileDto orderedTile = ContractCrossQueryService.getEstimateTile(
        ordered.history.Id
      );
      System.assertEquals(
        false,
        orderedTile.isEstimate,
        '横断画面.md 第5節 見積書タイル: Estimateだけ出す'
      );
      System.assertEquals(0, orderedTile.lines.size());
    }
  }

  @IsTest
  static void getEstimateTile_taxInclusiveAndCycleCount() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      HistoryFixture estimate = insertHistory(
        'Estimate',
        ContractCrossQueryService.organizationToday(),
        'QTile Tax'
      );
      Product2 recurring = ContractTestDataFactory.buildProduct(
        'Tile Recurring'
      );
      recurring.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(recurring);
      Product2 oneTime = ContractTestDataFactory.buildProduct('Tile OneTime');
      oneTime.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      ContractTestDataFactory.insertProduct(oneTime);

      Date startDate = ContractTestDataFactory.stableTermStart();
      Date endDate = ContractTestDataFactory.stableTermEnd(12);
      ContractProduct__c recurringLine = new ContractProduct__c(
        ContractHistory__c = estimate.history.Id,
        Product__c = recurring.Id,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        Amount__c = 12000,
        StartDate__c = startDate,
        Enddate__c = endDate,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New',
        RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_OVER_TIME
      );
      ContractTestDataFactory.applyRequiredFields(recurringLine);
      recurringLine.Account__c = null;
      ContractProduct__c oneTimeLine = new ContractProduct__c(
        ContractHistory__c = estimate.history.Id,
        Product__c = oneTime.Id,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        Amount__c = 1000,
        StartDate__c = startDate,
        Enddate__c = startDate,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME,
        Type__c = 'New',
        RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME
      );
      ContractTestDataFactory.applyRequiredFields(oneTimeLine);
      oneTimeLine.Account__c = null;
      insert new List<ContractProduct__c>{ recurringLine, oneTimeLine };

      ContractCrossController.EstimateTileDto tile = ContractCrossQueryService.getEstimateTile(
        estimate.history.Id
      );
      Decimal excl = [
          SELECT DeltaAmountSum__c
          FROM ContractHistory__c
          WHERE Id = :estimate.history.Id
        ]
        .DeltaAmountSum__c;
      System.assertEquals(
        TaxCalculationUtil.calculateAmountInclTax(excl, 10),
        tile.taxInclusiveAmount,
        '横断画面.md 第5節 見積書タイル: 税込は税抜へ税率を1回。Core 第4.6節'
      );
      Map<String, ContractCrossController.EstimateProductDto> byName = new Map<String, ContractCrossController.EstimateProductDto>();
      for (ContractCrossController.EstimateProductDto line : tile.lines) {
        byName.put(line.productName, line);
      }
      System.assertEquals(
        12,
        byName.get('Tile Recurring').cycleCount,
        '横断画面.md 第5節: 継続のサイクル数は期間から。Core 第4.6節'
      );
      System.assertEquals(
        '12',
        byName.get('Tile Recurring').cycleCountLabel
      );
      System.assertEquals(
        '-',
        byName.get('Tile OneTime').cycleCountLabel,
        '横断画面.md 第5節: 一回課金のサイクル数は `-`'
      );
    }
  }

  private static void enableAccounting() {
    List<GlAccountingPolicy__c> rows = [SELECT Id FROM GlAccountingPolicy__c];
    if (rows.isEmpty()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      return;
    }
    rows[0].AccountingEnabled__c = true;
    update rows[0];
  }

  private class HistoryFixture {
    ContractHistory__c history;
    Opportunity opportunity;
    BillingAccount__c billingAccount;
  }

  private static HistoryFixture insertHistory(
    String status,
    Date closeDate,
    String name
  ) {
    Account account = ContractTestDataFactory.insertAccount(
      name + ' Acc ' + String.valueOf(Crypto.getRandomInteger())
    );
    ContractService__c service = ContractTestDataFactory.insertContractService(
      account.Id,
      name + ' Svc'
    );
    ContractHistory__c history = new ContractHistory__c(
      Name = name,
      ContractService__c = service.Id,
      Type__c = 'New',
      historystatus__c = status,
      Version__c = 1
    );
    ContractTestDataFactory.applyRequiredFields(history);
    ContractTestDataFactory.applyEstimateOrderedOpportunity(history, account.Id);
    insert history;
    Opportunity opportunity = [
      SELECT Id, Name, AccountId, CloseDate
      FROM Opportunity
      WHERE Id = :history.Opportunity__c
    ];
    opportunity.CloseDate = closeDate;
    update opportunity;
    HistoryFixture fixture = new HistoryFixture();
    fixture.history = history;
    fixture.opportunity = opportunity;
    fixture.billingAccount = [
      SELECT Id
      FROM BillingAccount__c
      WHERE Id = :service.BiilingAcccount__c
    ];
    return fixture;
  }

  private class InvoiceFixture {
    Invoice__c invoice;
  }

  private static InvoiceFixture insertInvoice(String status) {
    HistoryFixture historyFixture = insertHistory(
      'Ordered',
      ContractCrossQueryService.organizationToday(),
      'QInv ' + status
    );
    Invoice__c invoice = new Invoice__c(
      ContractService__c = historyFixture.history.ContractService__c,
      ContractHistory__c = historyFixture.history.Id,
      InvoiceDate__c = Date.newInstance(2026, 6, 1),
      Amount__c = 1000,
      TaxAmount__c = 100,
      BillingAccountSnapShot__c = historyFixture.billingAccount.Id,
      InvoiceTransactionStatus__c = status,
      SystemIntegrationDate__c = status == 'Confirmed'
        ? ContractCrossQueryService.organizationToday()
        : null
    );
    ContractTestDataFactory.insertAllowingInvoiceStatus(invoice);
    InvoiceFixture fixture = new InvoiceFixture();
    fixture.invoice = invoice;
    return fixture;
  }

  private static GlJournal__c insertJournal(
    Id invoiceId,
    Boolean locked,
    String transactionStatus,
    Date postingDate,
    String keySuffix
  ) {
    GlAccount__c debit = new GlAccount__c(
      Name = keySuffix + ' Debit',
      AccountType__c = 'Asset',
      IsActive__c = true
    );
    GlAccount__c credit = new GlAccount__c(
      Name = keySuffix + ' Credit',
      AccountType__c = 'Liability',
      IsActive__c = true
    );
    insert new List<GlAccount__c>{ debit, credit };
    GlJournal__c journal = new GlJournal__c(
      Invoice__c = invoiceId,
      Amount__c = 1,
      IdempotencyKey__c = AccountingDiffService.hashKey(
        new List<String>{ keySuffix, String.valueOf(invoiceId) }
      ),
      DebitSlotKey__c = 'Cash',
      CreditSlotKey__c = 'UnappliedCash',
      DebitAccount__c = debit.Id,
      CreditAccount__c = credit.Id,
      PostingDate__c = postingDate,
      TransactionStatus__c = transactionStatus,
      IsLocked__c = locked
    );
    insert journal;
    return journal;
  }
}
