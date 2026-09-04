@IsTest
private class ContractCrossControllerTest {
  /** 仕様: 横断画面.md 第5節。請求一覧の準備は同一契約履歴へ載せて照会する。 */
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
    ContractTestDataFactory.ensureOrgDocumentSetting();
    insert GlAccountingPolicyService.newOrgDefault();
  }

  @IsTest
  static void getBootstrap_hidesJournalsWhenAccountingOff() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractCrossController.BootstrapDto dto = ContractCrossController.getBootstrap();
      System.assertEquals(
        false,
        dto.accountingEnabled,
        '横断画面.md 第2.4節: Accounting OFFでは仕訳一覧を出さない'
      );
      System.assertEquals(
        ContractDocumentSettingService.requireSendMode('Estimate'),
        dto.estimateSendMode,
        '横断画面.md 第1節: 見積書3択を返す'
      );
      System.assertEquals(
        ContractDocumentSettingService.requireSendMode('Invoice'),
        dto.invoiceSendMode,
        '横断画面.md 第1節: 請求書3択を返す'
      );
      System.assertEquals(
        ContractCrossQueryService.defaultEstimateCloseDates().dateFrom,
        dto.estimateCloseFrom,
        '完了予定日 FROM は今日の90日前'
      );
      System.assertEquals(
        ContractCrossQueryService.defaultEstimateCloseDates().dateTo,
        dto.estimateCloseTo,
        '完了予定日 TO は今月末'
      );
    }
  }

  @IsTest
  static void getBootstrap_showsEstimateMenuWhenOnly06() {
    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.CROSS_WORK => true,
      ContractPermissionUtil.ISSUE_ESTIMATE => false,
      ContractPermissionUtil.SEND_ESTIMATE => false,
      ContractPermissionUtil.ORDER => true
    };
    try {
      ContractCrossController.BootstrapDto dto = ContractCrossController.getBootstrap();
      System.assertEquals(
        true,
        dto.canShowEstimateMenu,
        '共通基盤.md 第3.2節: 横断の見積メニューは 04 または 05 または 06'
      );
      System.assertEquals(true, dto.canOrder);
      System.assertEquals(false, dto.canIssueEstimate);
      System.assertEquals(false, dto.canSendEstimate);
    } finally {
      ContractPermissionUtil.testOverrides = null;
    }
  }

  @IsTest
  static void getEstimateIssueContext_rejectsNullHistory() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Boolean thrown = false;
      try {
        ContractCrossController.getEstimateIssueContext(null);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '契約履歴が指定されていません。',
          ex.getMessage(),
          '横断画面.md 操作4: 発行画面は契約履歴が要る'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void getEstimateIssueContext_blocksWhenCompanyNameBlank() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.CompanyName__c = '';
      update setting;
      HistoryFixture history = insertHistory(
        'Estimate',
        ContractCrossQueryService.organizationToday(),
        'Issue Co'
      );

      ContractCrossController.IssueContextDto dto = ContractCrossController.getEstimateIssueContext(
        history.history.Id
      );
      System.assertEquals(
        ContractDocumentSettingService.withDocumentSendHeading(
          ContractDocumentSettingService.MISSING_COMPANY_NAME_MESSAGE
        ),
        dto.companyBlockedReason,
        'Core 第11.3.1節・第7.10節: 会社名空なら見積発行を画面で止め、見出し名を付ける'
      );
    }
  }

  @IsTest
  static void getEstimateTile_omitsLinesWhenNotEstimate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      HistoryFixture ordered = insertHistory(
        'Ordered',
        ContractCrossQueryService.organizationToday(),
        'Ordered Tile'
      );
      ContractCrossController.EstimateTileDto tile = ContractCrossController.getEstimateTile(
        ordered.history.Id
      );
      System.assertEquals(false, tile.isEstimate);
      System.assertEquals(
        0,
        tile.lines.size(),
        '横断画面.md 見積書タイル: Estimate 以外は明細を出さない'
      );
    }
  }

  @IsTest
  static void getEstimateTile_rejectsWithout18() {
    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.CROSS_WORK => false
    };
    Boolean thrown = false;
    try {
      ContractCrossController.getEstimateTile(UserInfo.getUserId());
    } catch (AuraHandledException ex) {
      thrown = true;
    } finally {
      ContractPermissionUtil.testOverrides = null;
    }
    System.assertEquals(
      true,
      thrown,
      '共通基盤 第10.4節: 見積タイル読込は 18'
    );
  }

  @IsTest
  static void getEstimateIssueContext_returnsLatestIssuedDocument() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractTestDataFactory.ensureOrgDocumentSetting();
      HistoryFixture history = insertHistory(
        'Estimate',
        ContractCrossQueryService.organizationToday(),
        'Issued Pdf Est'
      );
      Id documentId = insertIssuedFile(history.history.Id);

      ContractCrossController.IssueContextDto dto = ContractCrossController.getEstimateIssueContext(
        history.history.Id
      );
      System.assertEquals(
        documentId,
        dto.latestIssuedContentDocumentId,
        '横断画面.md 操作4: 発行画面は最新PDFをダウンロードできる'
      );
    }
  }

  @IsTest
  static void getEstimateIssueContext_fileNameUsesOpportunityNameWhenTitleBlank() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractTestDataFactory.ensureOrgDocumentSetting();
      HistoryFixture history = insertHistory(
        'Estimate',
        ContractCrossQueryService.organizationToday(),
        'Title Opp Est'
      );
      System.assertEquals(null, history.history.EstimateTitleName__c);
      ContractCrossController.IssueContextDto dto = ContractCrossController.getEstimateIssueContext(
        history.history.Id
      );
      System.assert(
        dto.fileName.contains(
          EstimateDocumentService.sanitizeFileName(history.opportunity.Name)
        ),
        'Core 第11.3.2節: 見積件名が空ならファイル名のTitleは商談名'
      );
    }
  }

  @IsTest
  static void previewEstimateIssueFileName_rejectsWithout04() {
    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.CROSS_WORK => true,
      ContractPermissionUtil.ISSUE_ESTIMATE => false
    };
    Boolean thrown = false;
    try {
      ContractCrossController.previewEstimateIssueFileName(
        UserInfo.getUserId(),
        null
      );
    } catch (AuraHandledException ex) {
      thrown = true;
      System.assertEquals(
        '見積書を発行する権限がありません。',
        ex.getMessage(),
        '共通基盤 第1.4節・第10.4節: ファイル名プレビューも発行は 04'
      );
    } finally {
      ContractPermissionUtil.testOverrides = null;
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void previewEstimateIssueFileName_usesOpportunityWhenTitleBlank() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractTestDataFactory.ensureOrgDocumentSetting();
      HistoryFixture history = insertHistory(
        'Estimate',
        ContractCrossQueryService.organizationToday(),
        'Preview Title Est'
      );
      String fileName = ContractCrossController.previewEstimateIssueFileName(
        history.history.Id,
        'StandardEstimate'
      );
      System.assert(
        fileName.contains(
          EstimateDocumentService.sanitizeFileName(history.opportunity.Name)
        ),
        'Core 第11.3.2節: 見積件名が空ならファイル名のTitleは商談名'
      );
    }
  }

  @IsTest
  static void queryEstimates_returnsEstimateInDefaultCloseDateOnly() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Date today = ContractCrossQueryService.organizationToday();
      HistoryFixture inRange = insertHistory(
        'Estimate',
        today,
        'InRange Est'
      );
      insertHistory('Estimate', today.addYears(-1), 'Old Est');
      insertHistory('Ordered', today, 'Ordered Est');

      ContractCrossController.EstimateFilterDto filter = new ContractCrossController.EstimateFilterDto();
      ContractCrossQueryService.DateRange range = ContractCrossQueryService.defaultEstimateCloseDates();
      filter.closeDateFrom = range.dateFrom;
      filter.closeDateTo = range.dateTo;

      ContractCrossController.ListResultDto result = ContractCrossController.queryEstimates(
        filter
      );
      Set<Id> ids = new Set<Id>();
      for (ContractCrossController.EstimateRowDto row : result.estimates) {
        ids.add(row.id);
      }
      System.assertEquals(true, ids.contains(inRange.history.Id));
      System.assertEquals(
        1,
        result.estimates.size(),
        '横断画面.md 第5節: 状態はEstimateのみ。既定期間外は出さない'
      );

      ContractCrossController.EstimateTileDto tile = ContractCrossController.getEstimateTile(
        inRange.history.Id
      );
      System.assertEquals(true, tile.isEstimate);
      System.assertEquals(inRange.history.Name, tile.historyName);
      Decimal estimateExcl = [
          SELECT DeltaAmountSum__c
          FROM ContractHistory__c
          WHERE Id = :inRange.history.Id
        ]
        .DeltaAmountSum__c;
      System.assertEquals(
        estimateExcl,
        result.estimates[0].amount,
        '横断画面.md 第5節: 見積税抜は DeltaAmountSum__c。Core 第7.8.5節'
      );
      System.assertEquals(
        estimateExcl,
        tile.amount,
        '横断画面.md 第5節 見積書タイル: 見積税抜は DeltaAmountSum__c。Core 第7.8.5節'
      );
    }
  }

  @IsTest
  static void queryInvoices_defaultDraftExcludesCancelled() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      HistoryFixture historyFixture = insertHistory(
        'Ordered',
        ContractCrossQueryService.organizationToday(),
        'DraftExcl'
      );
      Invoice__c draft = newDraftInvoice(
        historyFixture,
        Date.newInstance(2026, 6, 1)
      );
      Invoice__c confirmed = newDraftInvoice(
        historyFixture,
        Date.newInstance(2026, 6, 1)
      );
      confirmed.InvoiceTransactionStatus__c = 'Confirmed';
      confirmed.SystemIntegrationDate__c = ContractCrossQueryService.organizationToday();
      Invoice__c cancelled = newDraftInvoice(
        historyFixture,
        Date.newInstance(2026, 6, 1)
      );
      cancelled.InvoiceTransactionStatus__c = 'Cancelled';
      ContractTestDataFactory.insertAllowingInvoiceStatus(
        new List<Invoice__c>{ draft, confirmed, cancelled }
      );

      ContractCrossController.InvoiceFilterDto filter = new ContractCrossController.InvoiceFilterDto();
      filter.invoiceStatus = ContractCrossQueryService.INVOICE_STATUS_DRAFT;
      filter.includeCancelled = false;
      filter.accountId = historyFixture.opportunity.AccountId;

      Test.startTest();
      ContractCrossController.ListResultDto result = ContractCrossController.queryInvoices(
        filter
      );
      Test.stopTest();
      Set<Id> ids = new Set<Id>();
      for (ContractCrossController.InvoiceRowDto row : result.invoices) {
        ids.add(row.id);
      }
      System.assertEquals(true, ids.contains(draft.Id));
      System.assertEquals(1, result.invoices.size());
      System.assertEquals(false, ids.contains(cancelled.Id));
    }
  }

  @IsTest
  static void queryInvoices_returnsLatestIssuedContentDocumentId() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      InvoiceFixture issued = insertInvoice('Draft');
      InvoiceFixture unissued = insertInvoice('Draft');
      Id documentId = insertIssuedFile(issued.invoice.Id);

      ContractCrossController.InvoiceFilterDto filter = new ContractCrossController.InvoiceFilterDto();
      filter.invoiceStatus = ContractCrossQueryService.INVOICE_STATUS_DRAFT;

      ContractCrossController.ListResultDto result = ContractCrossController.queryInvoices(
        filter
      );
      Map<Id, ContractCrossController.InvoiceRowDto> byId = new Map<Id, ContractCrossController.InvoiceRowDto>();
      for (ContractCrossController.InvoiceRowDto row : result.invoices) {
        byId.put(row.id, row);
      }
      System.assertEquals(
        true,
        byId.get(issued.invoice.Id).issued,
        '横断画面.md 操作23: 発行済みなら発行あり'
      );
      System.assertEquals(
        documentId,
        byId.get(issued.invoice.Id).latestIssuedContentDocumentId,
        '横断画面.md 操作23: 最新発行PDFのIdを返す'
      );
      System.assertEquals(
        false,
        byId.get(unissued.invoice.Id).issued
      );
      System.assertEquals(
        null,
        byId.get(unissued.invoice.Id).latestIssuedContentDocumentId
      );
    }
  }

  @IsTest
  static void queryInvoices_cancelledKeepsPreCancelIssuedPdf() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      InvoiceFixture cancelled = insertInvoice('Cancelled');
      Id documentId = insertIssuedFile(cancelled.invoice.Id);

      ContractCrossController.InvoiceFilterDto filter = new ContractCrossController.InvoiceFilterDto();
      filter.invoiceStatus = ContractCrossQueryService.INVOICE_STATUS_CONFIRMED;
      filter.includeCancelled = true;

      ContractCrossController.ListResultDto result = ContractCrossController.queryInvoices(
        filter
      );
      System.assertEquals(1, result.invoices.size());
      System.assertEquals(
        documentId,
        result.invoices[0].latestIssuedContentDocumentId,
        '横断画面.md 操作23: 取消済みは取消前のPDF'
      );
    }
  }

  @IsTest
  static void queryInvoices_dateRangeKeepsBlankInvoiceDate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      HistoryFixture historyFixture = insertHistory(
        'Ordered',
        ContractCrossQueryService.organizationToday(),
        'DateRange'
      );
      Invoice__c inRange = newDraftInvoice(
        historyFixture,
        Date.newInstance(2026, 6, 1)
      );
      Invoice__c blank = newDraftInvoice(historyFixture, null);
      Invoice__c outOfRange = newDraftInvoice(
        historyFixture,
        Date.newInstance(2025, 1, 1)
      );
      ContractTestDataFactory.insertAllowingInvoiceStatus(
        new List<Invoice__c>{ inRange, blank, outOfRange }
      );

      ContractCrossController.InvoiceFilterDto filter = new ContractCrossController.InvoiceFilterDto();
      filter.invoiceStatus = ContractCrossQueryService.INVOICE_STATUS_DRAFT;
      filter.invoiceDateFrom = Date.newInstance(2026, 5, 1);
      filter.invoiceDateTo = Date.newInstance(2026, 7, 1);
      filter.accountId = historyFixture.opportunity.AccountId;

      Test.startTest();
      ContractCrossController.ListResultDto result = ContractCrossController.queryInvoices(
        filter
      );
      Test.stopTest();
      Set<Id> ids = new Set<Id>();
      for (ContractCrossController.InvoiceRowDto row : result.invoices) {
        ids.add(row.id);
      }
      System.assertEquals(true, ids.contains(inRange.Id));
      System.assertEquals(
        true,
        ids.contains(blank.Id),
        '横断画面.md 第5節: 空の請求日を消さない'
      );
      System.assertEquals(false, ids.contains(outOfRange.Id));
    }
  }

  @IsTest
  static void getBootstrap_zeroPoliciesDoesNotMeanOff() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.MIGRATE_ALL => true
      };
      try {
        delete [SELECT Id FROM GlAccountingPolicy__c];
        Boolean thrown = false;
        try {
          ContractCrossQueryService.isAccountingEnabled();
        } catch (Exception ex) {
          thrown = true;
          System.assert(
            ex.getMessage().contains('Accounting会計方針がありません'),
            'Core 第1.1.10節・Accounting 第3.1節: 会計方針0件はOFFと埋めない'
          );
        }
        System.assertEquals(true, thrown);
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
    }
  }

  @IsTest
  static void queryInvoices_issuedFilterLooksPastFirst500() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      HistoryFixture historyFixture = insertHistory(
        'Ordered',
        ContractCrossQueryService.organizationToday(),
        'Issued500'
      );
      List<Invoice__c> invoices = new List<Invoice__c>();
      for (Integer i = 0; i < 500; i++) {
        invoices.add(
          newDraftInvoice(
            historyFixture,
            Date.newInstance(2026, 1, 1)
          )
        );
      }
      invoices.add(
        newDraftInvoice(historyFixture, Date.newInstance(2026, 12, 31))
      );
      ContractTestDataFactory.insertAllowingInvoiceStatus(invoices);
      insertIssuedFile(invoices[500].Id);

      ContractCrossController.InvoiceFilterDto filter = new ContractCrossController.InvoiceFilterDto();
      filter.invoiceStatus = ContractCrossQueryService.INVOICE_STATUS_DRAFT;
      filter.issued = true;

      Test.startTest();
      ContractCrossController.ListResultDto result = ContractCrossController.queryInvoices(
        filter
      );
      Test.stopTest();

      System.assertEquals(
        1,
        result.invoices.size(),
        '横断画面.md 第5節取得: 発行フィルタは500件窓の外も拾う'
      );
      System.assertEquals(invoices[500].Id, result.invoices[0].id);
      System.assertEquals(
        false,
        result.truncated,
        '横断画面.md 第5節取得: 切れていないときは警告を出さない'
      );
    }
  }

  @IsTest
  static void queryInvoices_nextAcceptanceFilterLooksPastFirst500() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      enableAccounting();
      HistoryFixture historyFixture = insertHistory(
        'Ordered',
        ContractCrossQueryService.organizationToday(),
        'NextAcc500'
      );
      List<Invoice__c> invoices = new List<Invoice__c>();
      for (Integer i = 0; i < 500; i++) {
        invoices.add(
          newDraftInvoice(
            historyFixture,
            Date.newInstance(2026, 1, 1)
          )
        );
      }
      invoices.add(
        newDraftInvoice(historyFixture, Date.newInstance(2026, 12, 31))
      );
      ContractTestDataFactory.insertAllowingInvoiceStatus(invoices);
      InvoiceLine__c inRange = new InvoiceLine__c(
        Invoice__c = invoices[500].Id,
        Amount__c = 1000,
        RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME,
        AcceptanceEndDate__c = Date.newInstance(2026, 6, 15)
      );
      InvoiceLine__c outOfWindow = new InvoiceLine__c(
        Invoice__c = invoices[0].Id,
        Amount__c = 1000,
        RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME,
        AcceptanceEndDate__c = Date.newInstance(2026, 1, 15)
      );
      insert new List<InvoiceLine__c>{ inRange, outOfWindow };

      ContractCrossController.InvoiceFilterDto filter = new ContractCrossController.InvoiceFilterDto();
      filter.invoiceStatus = ContractCrossQueryService.INVOICE_STATUS_DRAFT;
      filter.nextAcceptanceFrom = Date.newInstance(2026, 6, 1);
      filter.nextAcceptanceTo = Date.newInstance(2026, 6, 30);

      Test.startTest();
      ContractCrossController.ListResultDto result = ContractCrossController.queryInvoices(
        filter
      );
      Test.stopTest();

      System.assertEquals(
        1,
        result.invoices.size(),
        '横断画面.md 第5節取得: 次の検収フィルタは500件窓の外も拾う'
      );
      System.assertEquals(invoices[500].Id, result.invoices[0].id);
      System.assertEquals(
        false,
        result.truncated,
        '横断画面.md 第5節取得: 切れていないときは警告を出さない'
      );
    }
  }

  @IsTest
  static void queryJournals_excludesLogicallyDeletedAndUsesLastMonthUnlocked() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      enableAccounting();
      InvoiceFixture fixture = insertInvoice('Confirmed');
      Date lastMonthDay = ContractCrossQueryService.defaultJournalPostingDates()
        .dateFrom;
      GlJournal__c unlocked = insertJournal(
        fixture.invoice.Id,
        false,
        'Active',
        lastMonthDay,
        'UNLOCKED'
      );
      insertJournal(
        fixture.invoice.Id,
        true,
        'Active',
        lastMonthDay,
        'LOCKED'
      );
      insertJournal(
        fixture.invoice.Id,
        false,
        'LogicallyDeleted',
        lastMonthDay,
        'DELETED'
      );
      insertJournal(
        fixture.invoice.Id,
        false,
        'Active',
        ContractCrossQueryService.organizationToday(),
        'THISMONTH'
      );

      ContractCrossController.JournalFilterDto filter = new ContractCrossController.JournalFilterDto();
      ContractCrossQueryService.DateRange range = ContractCrossQueryService.defaultJournalPostingDates();
      filter.postingDateFrom = range.dateFrom;
      filter.postingDateTo = range.dateTo;
      filter.lockState = ContractCrossQueryService.LOCK_UNLOCKED;

      ContractCrossController.ListResultDto result = ContractCrossController.queryJournals(
        filter
      );
      System.assertEquals(1, result.journals.size());
      System.assertEquals(unlocked.Id, result.journals[0].id);
      System.assertEquals(fixture.history.Id, result.journals[0].historyId);
      System.assertEquals(
        false,
        result.journals[0].invoiceCancelled,
        'Core 第12.2節: 未取消の請求は invoiceCancelled=false'
      );
    }
  }

  @IsTest
  static void queryJournals_marksCancelledInvoice() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      enableAccounting();
      InvoiceFixture fixture = insertInvoice('Cancelled');
      Date lastMonthDay = ContractCrossQueryService.defaultJournalPostingDates()
        .dateFrom;
      GlJournal__c journal = insertJournal(
        fixture.invoice.Id,
        false,
        'Active',
        lastMonthDay,
        'CANCELLEDINV'
      );

      ContractCrossController.JournalFilterDto filter = new ContractCrossController.JournalFilterDto();
      ContractCrossQueryService.DateRange range = ContractCrossQueryService.defaultJournalPostingDates();
      filter.postingDateFrom = range.dateFrom;
      filter.postingDateTo = range.dateTo;
      filter.lockState = ContractCrossQueryService.LOCK_UNLOCKED;

      ContractCrossController.ListResultDto result = ContractCrossController.queryJournals(
        filter
      );
      System.assertEquals(1, result.journals.size());
      System.assertEquals(journal.Id, result.journals[0].id);
      System.assertEquals(
        true,
        result.journals[0].invoiceCancelled,
        'Core 第12.2節・第7.7.3節: 取消済み請求の仕訳は参照だけ'
      );
    }
  }

  @IsTest
  static void queryJournals_truncatesAt500() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      enableAccounting();
      InvoiceFixture fixture = insertInvoice('Confirmed');
      Date posting = ContractCrossQueryService.defaultJournalPostingDates()
        .dateFrom;
      GlAccount__c debit = new GlAccount__c(
        Name = 'Trunc Debit',
        AccountType__c = 'Asset',
        IsActive__c = true
      );
      GlAccount__c credit = new GlAccount__c(
        Name = 'Trunc Credit',
        AccountType__c = 'Liability',
        IsActive__c = true
      );
      insert new List<GlAccount__c>{ debit, credit };
      List<GlJournal__c> rows = new List<GlJournal__c>();
      for (Integer i = 0; i < 501; i++) {
        rows.add(
          new GlJournal__c(
            Invoice__c = fixture.invoice.Id,
            Amount__c = 1,
            IdempotencyKey__c = ('C255' +
              String.valueOf(i).leftPad(4, '0') +
              String.valueOf(fixture.invoice.Id))
              .left(64),
            DebitSlotKey__c = 'Cash',
            CreditSlotKey__c = 'UnappliedCash',
            DebitAccount__c = debit.Id,
            CreditAccount__c = credit.Id,
            PostingDate__c = posting,
            TransactionStatus__c = 'Active',
            IsLocked__c = false
          )
        );
      }
      insert rows;

      ContractCrossController.JournalFilterDto filter = new ContractCrossController.JournalFilterDto();
      ContractCrossQueryService.DateRange range = ContractCrossQueryService.defaultJournalPostingDates();
      filter.postingDateFrom = range.dateFrom;
      filter.postingDateTo = range.dateTo;
      filter.lockState = ContractCrossQueryService.LOCK_UNLOCKED;

      Test.startTest();
      ContractCrossController.ListResultDto result = ContractCrossController.queryJournals(
        filter
      );
      Test.stopTest();
      System.assertEquals(true, result.truncated);
      System.assertEquals(
        ContractCrossQueryService.TRUNCATED_MESSAGE,
        result.truncatedMessage
      );
      System.assertEquals(500, result.journals.size());
    }
  }

  @IsTest
  static void saveJournals_memoOnlyDoesNotRefresh() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      enableAccounting();
      InvoiceFixture fixture = insertInvoice('Confirmed');
      GlJournal__c journal = insertJournal(
        fixture.invoice.Id,
        false,
        'Active',
        ContractCrossQueryService.defaultJournalPostingDates().dateFrom,
        'MEMOONLY'
      );
      ContractCrossController.JournalSaveRequestDto request = new ContractCrossController.JournalSaveRequestDto();
      request.checkedJournalIds = new List<Id>();
      ContractCrossController.JournalMemoDraftDto draft = new ContractCrossController.JournalMemoDraftDto();
      draft.journalId = journal.Id;
      draft.invoiceId = fixture.invoice.Id;
      draft.memo = '確認メモ';
      request.memos = new List<ContractCrossController.JournalMemoDraftDto>{
        draft
      };
      request.lockState = ContractCrossQueryService.LOCK_UNLOCKED;

      ContractCrossController.JournalSaveResultDto result = ContractCrossController.saveJournals(
        request
      );
      System.assertEquals(false, result.refreshed);
      System.assertEquals(
        '確認メモ',
        [SELECT Memo__c FROM GlJournal__c WHERE Id = :journal.Id].Memo__c
      );
    }
  }

  @IsTest
  static void saveJournals_lockFailureDoesNotWriteMemo() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      enableAccounting();
      InvoiceFixture fixture = insertInvoice('Confirmed');
      GlJournal__c journal = insertJournal(
        fixture.invoice.Id,
        false,
        'Active',
        ContractCrossQueryService.defaultJournalPostingDates().dateFrom,
        'LOCKFAIL'
      );
      ContractCrossController.JournalSaveRequestDto request = new ContractCrossController.JournalSaveRequestDto();
      request.checkedJournalIds = new List<Id>{ journal.Id };
      ContractCrossController.JournalMemoDraftDto draft = new ContractCrossController.JournalMemoDraftDto();
      draft.journalId = journal.Id;
      draft.invoiceId = fixture.invoice.Id;
      draft.memo = '書いてはいけない';
      request.memos = new List<ContractCrossController.JournalMemoDraftDto>{
        draft
      };
      request.lockState = ContractCrossQueryService.LOCK_UNLOCKED;
      request.invoiceTokens = new Map<String, String>{
        String.valueOf(fixture.invoice.Id) => 'bad-token'
      };

      Boolean thrown = false;
      try {
        ContractCrossController.saveJournals(request);
      } catch (AuraHandledException ex) {
        thrown = true;
      }
      System.assertEquals(true, thrown);
      System.assertEquals(
        null,
        [SELECT Memo__c FROM GlJournal__c WHERE Id = :journal.Id].Memo__c,
        '横断画面.md 第2.4節: Lock拒否時はメモも書かない'
      );
      System.assertEquals(
        false,
        [SELECT IsLocked__c FROM GlJournal__c WHERE Id = :journal.Id]
          .IsLocked__c
      );
    }
  }

  @IsTest
  static void saveJournals_extraOnlyDoesNotRefresh() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      enableAccounting();
      InvoiceOpsFieldService.setCachedRowsForTest(
        new List<InvoiceOpsField__mdt>{
          new InvoiceOpsField__mdt(
            DeveloperName = 'JnlUnlockReason',
            Active__c = true,
            TargetObject__c = 'GlJournal__c',
            FieldApiName__c = 'UnlockReason__c'
          )
        }
      );
      InvoiceFixture fixture = insertInvoice('Confirmed');
      GlJournal__c journal = insertJournal(
        fixture.invoice.Id,
        false,
        'Active',
        ContractCrossQueryService.defaultJournalPostingDates().dateFrom,
        'EXTRAONLY'
      );
      ContractCrossController.JournalSaveRequestDto request = new ContractCrossController.JournalSaveRequestDto();
      request.checkedJournalIds = new List<Id>();
      ContractCrossController.JournalMemoDraftDto draft = new ContractCrossController.JournalMemoDraftDto();
      draft.journalId = journal.Id;
      draft.invoiceId = fixture.invoice.Id;
      draft.memo = journal.Memo__c;
      draft.extraFieldValues = new Map<String, Object>{
        'UnlockReason__c' => '横断追加'
      };
      request.memos = new List<ContractCrossController.JournalMemoDraftDto>{
        draft
      };
      request.lockState = ContractCrossQueryService.LOCK_UNLOCKED;

      ContractCrossController.JournalSaveResultDto result = ContractCrossController.saveJournals(
        request
      );
      System.assertEquals(
        false,
        result.refreshed,
        '横断画面.md 第2.4節: 追加項目だけの保存では左を取り直さない'
      );
      System.assertEquals(
        '横断追加',
        [SELECT UnlockReason__c FROM GlJournal__c WHERE Id = :journal.Id]
          .UnlockReason__c
      );
      InvoiceOpsFieldService.resetCache();
    }
  }

  @IsTest
  static void saveJournals_lockFailureDoesNotWriteExtra() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      enableAccounting();
      InvoiceOpsFieldService.setCachedRowsForTest(
        new List<InvoiceOpsField__mdt>{
          new InvoiceOpsField__mdt(
            DeveloperName = 'JnlUnlockReason',
            Active__c = true,
            TargetObject__c = 'GlJournal__c',
            FieldApiName__c = 'UnlockReason__c'
          )
        }
      );
      InvoiceFixture fixture = insertInvoice('Confirmed');
      GlJournal__c journal = insertJournal(
        fixture.invoice.Id,
        false,
        'Active',
        ContractCrossQueryService.defaultJournalPostingDates().dateFrom,
        'LOCKXTRA'
      );
      ContractCrossController.JournalSaveRequestDto request = new ContractCrossController.JournalSaveRequestDto();
      request.checkedJournalIds = new List<Id>{ journal.Id };
      ContractCrossController.JournalMemoDraftDto draft = new ContractCrossController.JournalMemoDraftDto();
      draft.journalId = journal.Id;
      draft.invoiceId = fixture.invoice.Id;
      draft.memo = '書いてはいけない';
      draft.extraFieldValues = new Map<String, Object>{
        'UnlockReason__c' => '書いてはいけない追加'
      };
      request.memos = new List<ContractCrossController.JournalMemoDraftDto>{
        draft
      };
      request.lockState = ContractCrossQueryService.LOCK_UNLOCKED;
      request.invoiceTokens = new Map<String, String>{
        String.valueOf(fixture.invoice.Id) => 'bad-token'
      };

      Boolean thrown = false;
      try {
        ContractCrossController.saveJournals(request);
      } catch (AuraHandledException ex) {
        thrown = true;
      }
      System.assertEquals(true, thrown);
      GlJournal__c after = [
        SELECT Memo__c, UnlockReason__c, IsLocked__c
        FROM GlJournal__c
        WHERE Id = :journal.Id
      ];
      System.assertEquals(
        null,
        after.Memo__c,
        '横断画面.md 第2.4節: Lock拒否時はメモも書かない'
      );
      System.assertEquals(
        null,
        after.UnlockReason__c,
        '横断画面.md 第2.4節: Lock拒否時は追加項目も書かない'
      );
      System.assertEquals(false, after.IsLocked__c);
      InvoiceOpsFieldService.resetCache();
    }
  }

  @IsTest
  static void saveJournals_lockWithMemoWritesLockNotJournalMemo() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      enableAccounting();
      InvoiceFixture fixture = insertInvoice('Confirmed');
      GlJournal__c journal = insertJournal(
        fixture.invoice.Id,
        false,
        'Active',
        ContractCrossQueryService.defaultJournalPostingDates().dateFrom,
        'LOCKMEMO'
      );
      ContractCrossController.JournalSaveRequestDto request = new ContractCrossController.JournalSaveRequestDto();
      request.checkedJournalIds = new List<Id>{ journal.Id };
      ContractCrossController.JournalMemoDraftDto draft = new ContractCrossController.JournalMemoDraftDto();
      draft.journalId = journal.Id;
      draft.invoiceId = fixture.invoice.Id;
      draft.memo = 'Lock込み';
      request.memos = new List<ContractCrossController.JournalMemoDraftDto>{
        draft
      };
      request.lockState = ContractCrossQueryService.LOCK_UNLOCKED;
      request.invoiceTokens = new Map<String, String>{
        String.valueOf(fixture.invoice.Id) => AccountingCauseLockService.resolveInvoiceOperationToken(
          fixture.invoice.Id
        )
      };

      ContractCrossController.saveJournals(request);

      System.assertEquals(
        true,
        [SELECT IsLocked__c FROM GlJournal__c WHERE Id = :journal.Id]
          .IsLocked__c
      );
      System.assertEquals(
        'Lock込み',
        [SELECT Memo__c FROM GlJournal__c WHERE Id = :journal.Id].Memo__c
      );
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM ContractOperationLog__c
          WHERE OperationType__c = 'LockJournal'
        ],
        '共通基盤第12章: 横断のLock込み保存はLock種別'
      );
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM ContractOperationLog__c
          WHERE OperationType__c = 'JournalMemo'
        ],
        '共通基盤第12章: Lock込み保存はJournalMemo行を作らない'
      );
    }
  }

  @IsTest
  static void queryJournals_returnsExtraFieldValues() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      enableAccounting();
      InvoiceOpsFieldService.setCachedRowsForTest(
        new List<InvoiceOpsField__mdt>{
          new InvoiceOpsField__mdt(
            DeveloperName = 'JnlUnlockReason',
            Active__c = true,
            TargetObject__c = 'GlJournal__c',
            FieldApiName__c = 'UnlockReason__c'
          )
        }
      );
      InvoiceFixture fixture = insertInvoice('Confirmed');
      GlJournal__c journal = insertJournal(
        fixture.invoice.Id,
        false,
        'Active',
        ContractCrossQueryService.defaultJournalPostingDates().dateFrom,
        'QEXTRA'
      );
      journal.UnlockReason__c = '列の値';
      update journal;

      ContractCrossController.JournalFilterDto filter = new ContractCrossController.JournalFilterDto();
      ContractCrossQueryService.DateRange range = ContractCrossQueryService.defaultJournalPostingDates();
      filter.postingDateFrom = range.dateFrom;
      filter.postingDateTo = range.dateTo;
      filter.lockState = ContractCrossQueryService.LOCK_UNLOCKED;

      ContractCrossController.ListResultDto result = ContractCrossController.queryJournals(
        filter
      );
      ContractCrossController.JournalRowDto found;
      for (ContractCrossController.JournalRowDto row : result.journals) {
        if (row.id == journal.Id) {
          found = row;
        }
      }
      System.assertNotEquals(null, found);
      System.assertEquals(
        '列の値',
        (String) found.extraFieldValues.get('UnlockReason__c'),
        'Core 第11.4.4節: 横断仕訳一覧は仕訳追加項目の値を返す'
      );
      InvoiceOpsFieldService.resetCache();
    }
  }

  @IsTest
  static void saveJournals_rejectsNullRequest() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Boolean thrown = false;
      try {
        ContractCrossController.saveJournals(null);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '保存する内容がありません。',
          ex.getMessage(),
          '横断画面.md 第2.4節: 保存する内容が無ければ実行できない'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void saveJournals_emptyWithoutCheckOrEditsThrows() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      enableAccounting();
      ContractCrossController.JournalSaveRequestDto request = new ContractCrossController.JournalSaveRequestDto();
      request.checkedJournalIds = new List<Id>();
      request.memos = new List<ContractCrossController.JournalMemoDraftDto>();
      Boolean thrown = false;
      try {
        ContractCrossController.saveJournals(request);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          'チェックが無くメモの変更も追加項目の変更も無ければ実行できません。',
          ex.getMessage(),
          '横断画面.md 第2.4節: チェックもメモも追加項目も無ければ実行できない'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void queryJournals_accountingOffThrows() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractCrossController.JournalFilterDto filter = new ContractCrossController.JournalFilterDto();
      ContractCrossQueryService.DateRange range = ContractCrossQueryService.defaultJournalPostingDates();
      filter.postingDateFrom = range.dateFrom;
      filter.postingDateTo = range.dateTo;
      filter.lockState = ContractCrossQueryService.LOCK_UNLOCKED;
      Boolean thrown = false;
      try {
        ContractCrossController.queryJournals(filter);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          'AccountingがOFFのときは仕訳一覧を出せません。',
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  private static void enableAccounting() {
    List<GlAccountingPolicy__c> rows = [
      SELECT Id
      FROM GlAccountingPolicy__c
    ];
    if (rows.isEmpty()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      return;
    }
    rows[0].AccountingEnabled__c = true;
    update rows[0];
  }

  private static Invoice__c newDraftInvoice(
    HistoryFixture historyFixture,
    Date invoiceDate
  ) {
    return new Invoice__c(
      ContractService__c = historyFixture.history.ContractService__c,
      ContractHistory__c = historyFixture.history.Id,
      InvoiceDate__c = invoiceDate,
      Amount__c = 1000,
      TaxAmount__c = 100,
      BillingAccountSnapShot__c = historyFixture.billingAccount.Id,
      InvoiceTransactionStatus__c = 'Draft'
    );
  }

  private static Id insertIssuedFile(Id invoiceId) {
    ContentVersion version = new ContentVersion(
      Title = 'issued',
      PathOnClient = 'issued.pdf',
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
      LinkedEntityId = invoiceId,
      ShareType = 'V',
      Visibility = 'AllUsers'
    );
    return documentId;
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
    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = account.Id,
      BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
      BillingEmailTo__c = 'cross@example.com',
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
    Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
      account.Id,
      name + ' Opp'
    );
    opportunity.CloseDate = closeDate;
    update opportunity;
    ContractService__c service = new ContractService__c(
      Name = name + ' Svc',
      Account__c = account.Id,
      BiilingAcccount__c = billingAccount.Id,
      TaxPercent__c = 0.1
    );
    insert service;
    ContractHistory__c history = new ContractHistory__c(
      Name = name,
      ContractService__c = service.Id,
      Opportunity__c = opportunity.Id,
      Type__c = 'New',
      historystatus__c = status,
      Version__c = 1
    );
    insert history;
    HistoryFixture fixture = new HistoryFixture();
    fixture.history = history;
    fixture.opportunity = opportunity;
    fixture.billingAccount = billingAccount;
    return fixture;
  }

  private class InvoiceFixture {
    Invoice__c invoice;
    ContractHistory__c history;
  }

  private static InvoiceFixture insertInvoice(String status) {
    HistoryFixture historyFixture = insertHistory(
      'Ordered',
      ContractCrossQueryService.organizationToday(),
      'Inv ' + status
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
    fixture.history = historyFixture.history;
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
