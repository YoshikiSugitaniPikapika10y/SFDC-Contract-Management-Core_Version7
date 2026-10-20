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
  static void crossRead_doesNotFailWithoutFieldRead() {
    User limited = ContractTestDataFactory.getUserWithoutContractHistoryFieldRead();
    System.runAs(limited) {
      System.assertEquals(
        false,
        ContractHistory__c.EstimateDate__c.getDescribe().isAccessible(),
        '共通基盤 第1.3節: この利用者は見積日を参照できない'
      );
      String prefix = ContractHistory__c.SObjectType.getDescribe()
        .getKeyPrefix();
      Id missingId = (Id) (prefix + '000000000001');
      System.assertEquals(
        null,
        ContractCrossQueryService.queryHistoryForEstimateIssue(missingId),
        '共通基盤 第1.3節: 見積日を参照できなくても04の発行前読取は権限例外にしない'
      );
      Boolean accessFailure = false;
      try {
        ContractCrossQueryService.getEstimateTile(missingId);
      } catch (ContractCrossQueryService.QueryException ex) {
        System.assert(
          ex.getMessage().contains('見つかりません'),
          ex.getMessage()
        );
      } catch (Exception ex) {
        accessFailure = true;
        System.assert(false, ex.getTypeName() + ' ' + ex.getMessage());
      }
      System.assertEquals(false, accessFailure);
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
  static void queryEstimates_issuedMeansPdfNotIssueDate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Date today = ContractCrossQueryService.organizationToday();
      HistoryFixture inRange = insertHistory('Estimate', today, 'QEst Pdf');
      inRange.history.EstimateIssueDate__c = today;
      update inRange.history;

      ContractCrossController.EstimateFilterDto filter = new ContractCrossController.EstimateFilterDto();
      ContractCrossQueryService.DateRange range = ContractCrossQueryService.defaultEstimateCloseDates();
      filter.closeDateFrom = range.dateFrom;
      filter.closeDateTo = range.dateTo;
      filter.accountId = inRange.opportunity.AccountId;
      filter.issued = true;
      System.assertEquals(
        0,
        ContractCrossQueryService.queryEstimates(filter).estimates.size(),
        '共通基盤: 発行日だけでは発行ありにしない'
      );

      filter.issued = null;
      ContractCrossController.ListResultDto listed = ContractCrossQueryService.queryEstimates(
        filter
      );
      System.assertEquals(1, listed.estimates.size());
      System.assertEquals(
        false,
        listed.estimates[0].issued,
        '共通基盤: 見積書PDFが無い見積は発行ありではない'
      );

      ContentVersion version = new ContentVersion(
        Title = 'estimate',
        PathOnClient = 'estimate.pdf',
        VersionData = Blob.valueOf('pdf'),
        ContractDocumentIssued__c = true
      );
      insert version;
      Id documentId = [
        SELECT ContentDocumentId
        FROM ContentVersion
        WHERE Id = :version.Id
      ]
      .ContentDocumentId;
      insert new ContentDocumentLink(
        ContentDocumentId = documentId,
        LinkedEntityId = inRange.history.Id,
        ShareType = 'V',
        Visibility = 'AllUsers'
      );

      filter.issued = true;
      ContractCrossController.ListResultDto withPdf = ContractCrossQueryService.queryEstimates(
        filter
      );
      System.assertEquals(
        1,
        withPdf.estimates.size(),
        '共通基盤: 見積書PDFがある見積だけ発行あり'
      );
      System.assertEquals(true, withPdf.estimates[0].issued);
      System.assertEquals(inRange.history.Id, withPdf.estimates[0].id);
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
  static void queryInvoices_tagUnsetTrueAndFalseSplit() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      enableAccounting();
      insert new GlAccountingTagRule__c(
        Name = '手動調整タグ',
        TagKey__c = 'amount-adjusted',
        TagLabel__c = '手動調整',
        Expression__c = 'AR',
        ComparisonOperator__c = 'NE',
        ComparisonValue__c = 0,
        TargetFieldApiName__c = 'IsAmountAdjusted__c',
        IsEnabled__c = true
      );
      HistoryFixture historyFixture = insertHistory(
        'Ordered',
        ContractCrossQueryService.organizationToday(),
        'QInv Tag'
      );
      Invoice__c tagged = new Invoice__c(
        ContractService__c = historyFixture.history.ContractService__c,
        ContractHistory__c = historyFixture.history.Id,
        InvoiceDate__c = Date.newInstance(2026, 6, 1),
        Amount__c = 1000,
        TaxAmount__c = 100,
        BillingAccountSnapShot__c = historyFixture.billingAccount.Id,
        InvoiceTransactionStatus__c = 'Draft',
        IsAmountAdjusted__c = true
      );
      Invoice__c untagged = new Invoice__c(
        ContractService__c = historyFixture.history.ContractService__c,
        ContractHistory__c = historyFixture.history.Id,
        InvoiceDate__c = Date.newInstance(2026, 6, 2),
        Amount__c = 1000,
        TaxAmount__c = 100,
        BillingAccountSnapShot__c = historyFixture.billingAccount.Id,
        InvoiceTransactionStatus__c = 'Draft',
        IsAmountAdjusted__c = false
      );
      ContractTestDataFactory.insertAllowingInvoiceStatus(tagged);
      ContractTestDataFactory.insertAllowingInvoiceStatus(untagged);

      ContractCrossController.InvoiceFilterDto filter = new ContractCrossController.InvoiceFilterDto();
      filter.invoiceStatus = ContractCrossQueryService.INVOICE_STATUS_DRAFT;
      filter.invoiceDateFrom = Date.newInstance(2026, 6, 1);
      filter.invoiceDateTo = Date.newInstance(2026, 6, 2);
      filter.accountId = historyFixture.opportunity.AccountId;
      ContractCrossController.ListResultDto unset = ContractCrossQueryService.queryInvoices(
        filter
      );
      Set<Id> unsetIds = invoiceIds(unset);
      System.assertEquals(
        true,
        unsetIds.contains(tagged.Id) && unsetIds.contains(untagged.Id),
        '共通基盤契約横断: 会計タグ未指定では真も偽も残す'
      );

      ContractCrossController.TagFilterDto trueFilter = new ContractCrossController.TagFilterDto();
      trueFilter.fieldApiName = 'IsAmountAdjusted__c';
      trueFilter.state = 'True';
      filter.tagFilters = new List<ContractCrossController.TagFilterDto>{
        trueFilter
      };
      Set<Id> trueIds = invoiceIds(
        ContractCrossQueryService.queryInvoices(filter)
      );
      System.assertEquals(
        true,
        trueIds.contains(tagged.Id) && !trueIds.contains(untagged.Id),
        '共通基盤契約横断: 会計タグが真の請求だけ残す'
      );

      filter.tagFilters[0].state = 'False';
      Set<Id> falseIds = invoiceIds(
        ContractCrossQueryService.queryInvoices(filter)
      );
      System.assertEquals(
        true,
        falseIds.contains(untagged.Id) && !falseIds.contains(tagged.Id),
        '共通基盤契約横断: 会計タグが偽の請求だけ残す'
      );

      ContractCrossController.InvoiceRowDto trueRow;
      for (ContractCrossController.InvoiceRowDto row : unset.invoices) {
        if (row.id == tagged.Id) {
          trueRow = row;
        }
      }
      System.assertEquals(
        true,
        trueRow != null && trueRow.trueTagLabels.contains('手動調整'),
        '共通基盤契約横断: 真の会計タグ名を請求行に載せる'
      );
      System.assertEquals(
        true,
        ContractCrossQueryService.loadEnabledTagRules().size() > 0,
        '共通基盤契約横断: 有効な会計タグは同じ処理で取り直さない'
      );
    }
  }

  @IsTest
  static void queryEstimates_sentAutoRenewAndTypeSplit() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Date today = ContractCrossQueryService.organizationToday();
      HistoryFixture sent = insertHistory('Estimate', today, 'QEst Sent Side');
      HistoryFixture plain = insertHistory(
        'Estimate',
        today,
        'QEst Plain Side'
      );
      sent.history.EstimateSentAt__c = Datetime.newInstance(
        2026,
        6,
        1,
        9,
        0,
        0
      );
      sent.history.Type__c = 'Change';
      update sent.history;
      Boolean previousAllow = ContractHistoryTriggerHandler.allowRenewEstimateAutoCreatedWrite;
      ContractHistoryTriggerHandler.allowRenewEstimateAutoCreatedWrite = true;
      try {
        plain.history.RenewEstimateAutoCreated__c = true;
        update plain.history;
      } finally {
        ContractHistoryTriggerHandler.allowRenewEstimateAutoCreatedWrite = previousAllow;
      }

      ContractCrossQueryService.DateRange range = ContractCrossQueryService.defaultEstimateCloseDates();
      ContractCrossController.EstimateFilterDto sentFilter = estimateFilter(
        range
      );
      sentFilter.accountId = sent.opportunity.AccountId;
      sentFilter.sent = true;
      System.assertEquals(
        1,
        ContractCrossQueryService.queryEstimates(sentFilter).estimates.size(),
        '共通基盤契約横断: 送付ありだけ残す'
      );
      sentFilter.sent = false;
      System.assertEquals(
        0,
        ContractCrossQueryService.queryEstimates(sentFilter).estimates.size(),
        '共通基盤契約横断: 送付なしでは送付ありを消す'
      );

      ContractCrossController.EstimateFilterDto plainFilter = estimateFilter(
        range
      );
      plainFilter.accountId = plain.opportunity.AccountId;
      plainFilter.sent = false;
      System.assertEquals(
        1,
        ContractCrossQueryService.queryEstimates(plainFilter).estimates.size(),
        '共通基盤契約横断: 送付なしだけ残す'
      );

      plainFilter.autoRenew = true;
      System.assertEquals(
        1,
        ContractCrossQueryService.queryEstimates(plainFilter).estimates.size(),
        '共通基盤契約横断: 自動更新ありだけ残す'
      );
      plainFilter.autoRenew = false;
      System.assertEquals(
        0,
        ContractCrossQueryService.queryEstimates(plainFilter).estimates.size(),
        '共通基盤契約横断: 自動更新なしでは自動更新ありを消す'
      );

      sentFilter.sent = null;
      sentFilter.estimateType = 'Change';
      System.assertEquals(
        1,
        ContractCrossQueryService.queryEstimates(sentFilter).estimates.size(),
        '共通基盤契約横断: 種別が変更の見積だけ残す'
      );
      sentFilter.estimateType = 'New';
      System.assertEquals(
        0,
        ContractCrossQueryService.queryEstimates(sentFilter).estimates.size(),
        '共通基盤契約横断: 種別が新規では変更を消す'
      );
    }
  }

  private static ContractCrossController.EstimateFilterDto estimateFilter(
    ContractCrossQueryService.DateRange range
  ) {
    ContractCrossController.EstimateFilterDto filter = new ContractCrossController.EstimateFilterDto();
    filter.closeDateFrom = range.dateFrom;
    filter.closeDateTo = range.dateTo;
    return filter;
  }

  private static Invoice__c invoiceOn(
    HistoryFixture historyFixture,
    String deliveryStatus,
    String collectionStatus,
    Date paymentScheduledDate
  ) {
    return new Invoice__c(
      ContractService__c = historyFixture.history.ContractService__c,
      ContractHistory__c = historyFixture.history.Id,
      InvoiceDate__c = Date.newInstance(2026, 6, 1),
      Amount__c = 1000,
      TaxAmount__c = 100,
      BillingAccountSnapShot__c = historyFixture.billingAccount.Id,
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED,
      SystemIntegrationDate__c = ContractCrossQueryService.organizationToday(),
      DeliveryStatus__c = deliveryStatus,
      CollectionRefundStatus__c = collectionStatus,
      PaymentScheduledDate__c = paymentScheduledDate
    );
  }

  private static Set<Id> journalIds(
    ContractCrossController.ListResultDto result
  ) {
    Set<Id> ids = new Set<Id>();
    if (result == null || result.journals == null) {
      return ids;
    }
    for (ContractCrossController.JournalRowDto row : result.journals) {
      ids.add(row.id);
    }
    return ids;
  }

  private static Set<Id> invoiceIds(
    ContractCrossController.ListResultDto result
  ) {
    Set<Id> ids = new Set<Id>();
    if (result == null || result.invoices == null) {
      return ids;
    }
    for (ContractCrossController.InvoiceRowDto row : result.invoices) {
      ids.add(row.id);
    }
    return ids;
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
  static void queryInvoices_sentOverdueAndCollectionSplit() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      HistoryFixture historyFixture = insertHistory(
        'Ordered',
        ContractCrossQueryService.organizationToday(),
        'QInv Split'
      );
      Date today = ContractCrossQueryService.organizationToday();
      Invoice__c sentLate = invoiceOn(
        historyFixture,
        InvoiceTransactionStatusService.DELIVERY_SENT,
        InvoiceTransactionStatusService.COLLECTION_NOT_STARTED,
        today.addDays(-1)
      );
      Invoice__c unsentOpen = invoiceOn(
        historyFixture,
        InvoiceTransactionStatusService.DELIVERY_UNSENT,
        InvoiceTransactionStatusService.COLLECTION_IN_PROGRESS,
        today.addDays(30)
      );
      Invoice__c unsentDone = invoiceOn(
        historyFixture,
        InvoiceTransactionStatusService.DELIVERY_UNSENT,
        InvoiceTransactionStatusService.COLLECTION_COMPLETED,
        today.addDays(30)
      );
      ContractTestDataFactory.insertAllowingInvoiceStatus(
        new List<Invoice__c>{ sentLate, unsentOpen, unsentDone }
      );

      ContractCrossController.InvoiceFilterDto filter = new ContractCrossController.InvoiceFilterDto();
      filter.invoiceStatus = ContractCrossQueryService.INVOICE_STATUS_CONFIRMED;
      filter.accountId = historyFixture.opportunity.AccountId;
      filter.sent = true;
      Set<Id> sentIds = invoiceIds(
        ContractCrossQueryService.queryInvoices(filter)
      );
      System.assertEquals(
        true,
        sentIds.contains(sentLate.Id) &&
          !sentIds.contains(unsentOpen.Id) &&
          !sentIds.contains(unsentDone.Id),
        '共通基盤契約横断: 送付ありは送付済みだけ残す'
      );
      filter.sent = false;
      Set<Id> unsentIds = invoiceIds(
        ContractCrossQueryService.queryInvoices(filter)
      );
      System.assertEquals(
        true,
        unsentIds.contains(unsentOpen.Id) &&
          unsentIds.contains(unsentDone.Id) &&
          !unsentIds.contains(sentLate.Id),
        '共通基盤契約横断: 送付なしは未送付だけ残す'
      );

      filter.sent = null;
      filter.overdue = true;
      Set<Id> lateIds = invoiceIds(
        ContractCrossQueryService.queryInvoices(filter)
      );
      System.assertEquals(
        true,
        lateIds.contains(sentLate.Id) &&
          !lateIds.contains(unsentOpen.Id) &&
          !lateIds.contains(unsentDone.Id),
        '共通基盤契約横断: 遅延ありは遅延の請求だけ残す'
      );
      filter.overdue = false;
      Set<Id> openIds = invoiceIds(
        ContractCrossQueryService.queryInvoices(filter)
      );
      System.assertEquals(
        true,
        openIds.contains(unsentOpen.Id) &&
          openIds.contains(unsentDone.Id) &&
          !openIds.contains(sentLate.Id),
        '共通基盤契約横断: 遅延なしは遅延以外を残す'
      );

      filter.overdue = null;
      filter.collectionStatus = InvoiceTransactionStatusService.COLLECTION_NOT_STARTED;
      Set<Id> notStarted = invoiceIds(
        ContractCrossQueryService.queryInvoices(filter)
      );
      filter.collectionStatus = InvoiceTransactionStatusService.COLLECTION_IN_PROGRESS;
      Set<Id> inProgress = invoiceIds(
        ContractCrossQueryService.queryInvoices(filter)
      );
      filter.collectionStatus = InvoiceTransactionStatusService.COLLECTION_COMPLETED;
      Set<Id> completed = invoiceIds(
        ContractCrossQueryService.queryInvoices(filter)
      );
      System.assertEquals(
        true,
        notStarted.contains(sentLate.Id) &&
          !notStarted.contains(unsentOpen.Id) &&
          inProgress.contains(unsentOpen.Id) &&
          !inProgress.contains(unsentDone.Id) &&
          completed.contains(unsentDone.Id) &&
          !completed.contains(sentLate.Id),
        '共通基盤契約横断: 未対応、対応中、完了で残る請求が分かれる'
      );
    }
  }

  @IsTest
  static void queryJournals_patternUnsetSpecifiedAndManualSplit() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      enableAccounting();
      GlAccountingPolicyService.clearCachedOrgPolicy();
      InvoiceFixture invoiceFixture = insertInvoice('Confirmed');
      Date postingDate = Date.newInstance(2026, 6, 15);
      GlAccount__c debit = new GlAccount__c(
        Name = 'QJnl Pattern Debit',
        AccountType__c = 'Expense',
        IsActive__c = true
      );
      GlAccount__c credit = new GlAccount__c(
        Name = 'QJnl Pattern Credit',
        AccountType__c = 'Asset',
        IsActive__c = true
      );
      insert new List<GlAccount__c>{ debit, credit };
      GlManualJournalSetting__c setting = new GlManualJournalSetting__c(
        Name = '横断の手動設定',
        DebitSlotKey__c = 'FxLoss',
        DebitAccount__c = debit.Id,
        CreditSlotKey__c = 'AccountsReceivable',
        CreditAccount__c = credit.Id,
        Description__c = '検証',
        IsActive__c = true
      );
      insert setting;
      GlJournal__c patterned = new GlJournal__c(
        Invoice__c = invoiceFixture.invoice.Id,
        Amount__c = 1,
        IdempotencyKey__c = AccountingDiffService.hashKey(
          new List<String>{
            'pattern',
            String.valueOf(invoiceFixture.invoice.Id)
          }
        ),
        DebitSlotKey__c = 'Cash',
        CreditSlotKey__c = 'UnappliedCash',
        DebitAccount__c = debit.Id,
        CreditAccount__c = credit.Id,
        PostingDate__c = postingDate,
        TransactionStatus__c = 'Active',
        IsLocked__c = false,
        JournalPatternKey__c = JournalPatternFixedCatalog.BILLING_BASIS_INVOICE_BODY.key
      );
      GlJournal__c manual = new GlJournal__c(
        Invoice__c = invoiceFixture.invoice.Id,
        Amount__c = 2,
        IdempotencyKey__c = AccountingDiffService.hashKey(
          new List<String>{
            'manual',
            String.valueOf(invoiceFixture.invoice.Id)
          }
        ),
        DebitSlotKey__c = 'Cash',
        CreditSlotKey__c = 'UnappliedCash',
        DebitAccount__c = debit.Id,
        CreditAccount__c = credit.Id,
        PostingDate__c = postingDate,
        TransactionStatus__c = 'Active',
        IsLocked__c = false,
        GlManualJournalSetting__c = setting.Id
      );
      insert new List<GlJournal__c>{ patterned, manual };

      ContractCrossController.JournalFilterDto filter = new ContractCrossController.JournalFilterDto();
      filter.postingDateFrom = postingDate;
      filter.postingDateTo = postingDate;
      filter.lockState = ContractCrossQueryService.LOCK_UNLOCKED;
      filter.invoiceId = invoiceFixture.invoice.Id;
      Set<Id> unsetIds = journalIds(
        ContractCrossQueryService.queryJournals(filter)
      );
      System.assertEquals(
        true,
        unsetIds.contains(patterned.Id) && unsetIds.contains(manual.Id),
        '共通基盤契約横断: パターン未指定ではパターン仕訳も手動設定も残す'
      );
      filter.eventKey = JournalPatternFixedCatalog.BILLING_BASIS_INVOICE_BODY.key;
      Set<Id> patternIds = journalIds(
        ContractCrossQueryService.queryJournals(filter)
      );
      System.assertEquals(
        true,
        patternIds.contains(patterned.Id) && !patternIds.contains(manual.Id),
        '共通基盤契約横断: 指定したパターンの仕訳だけ残す'
      );
      filter.eventKey = String.valueOf(setting.Id);
      Set<Id> manualIds = journalIds(
        ContractCrossQueryService.queryJournals(filter)
      );
      System.assertEquals(
        true,
        manualIds.contains(manual.Id) && !manualIds.contains(patterned.Id),
        '共通基盤契約横断: 指定した手動設定の仕訳だけ残す'
      );
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
      System.assertEquals('12', byName.get('Tile Recurring').cycleCountLabel);
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
    ContractTestDataFactory.applyEstimateOrderedOpportunity(
      history,
      account.Id
    );
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
