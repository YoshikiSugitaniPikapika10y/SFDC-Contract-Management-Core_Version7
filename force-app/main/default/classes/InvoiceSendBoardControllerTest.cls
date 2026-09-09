@IsTest
private class InvoiceSendBoardControllerTest {
  @TestSetup
  static void setup() {
    ContractTestDataFactory.initTestContext();
    ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
    setting.InvoiceSendMode__c = 'PdfAndEmail';
    setting.InvoiceOrgWideEmailAddress__c = ContractTestDataFactory.requireVerifiedOrgWideAddress();
    update setting;
    ContractDocumentSettingService.clearCache();
    insert GlAccountingPolicyService.newOrgDefault();
  }

  @IsTest
  static void contextAndList_returnConfiguredInvoices() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c confirmed = createInvoice(
        '一覧検索取引先',
        'Confirmed',
        'board@example.com'
      );
      Test.startTest();
      InvoiceSendBoardController.BoardContextDto context = InvoiceSendBoardController.getBoardContext();
      Test.stopTest();
      System.assertEquals(true, context.canSend);
      System.assertEquals(true, context.featureEnabled);
      System.assertEquals(500, context.listLimit);
      System.assertEquals('StandardInvoice', context.defaultDocumentTemplateKey);
      System.assertEquals(
        'Contract_Standard_Invoice_Email',
        context.defaultEmailTemplateApiName
      );
      System.assert(
        !context.documentTemplateOptions.isEmpty(),
        'Invoice帳票テンプレートが返ること'
      );
      System.assert(
        !context.emailTemplateOptions.isEmpty(),
        'Invoice送付メールテンプレートが返ること'
      );
      System.assertNotEquals(null, confirmed.Id);
    }
  }

  @IsTest
  static void confirmInvoiceFromPreview_confirmsDraft() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = createInvoice(
        '確定取消テスト取引先',
        'Draft',
        'confirm@example.com'
      );

      Test.startTest();
      InvoiceSendBoardController.ConfirmResultDto confirmed = InvoiceSendBoardController.confirmInvoiceFromPreview(
        invoice.Id,
        Date.today(),
        currentToken(invoice.Id),
        null,
        invoice.ContractHistory__c
      );
      Test.stopTest();
      System.assertEquals(1, confirmed.confirmedCount);
      System.assertEquals(
        null,
        confirmed.issueWarning,
        'Core 第7.10節: 確定はPDFを付けない'
      );
      System.assertEquals(
        true,
        String.isNotBlank(confirmed.businessOperationKey),
        'Core 第7.9.7節: 確定は業務操作キーを発行して返す'
      );
      Invoice__c confirmedInvoice = [
        SELECT
          InvoiceTransactionStatus__c,
          SystemIntegrationDate__c,
          BusinessOperationKey__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(
        confirmed.businessOperationKey,
        confirmedInvoice.BusinessOperationKey__c,
        'Core 第7.9.7節: 発行したキーを請求へ書く'
      );
      System.assertEquals(
        InvoiceTransactionStatusService.TX_CONFIRMED,
        confirmedInvoice.InvoiceTransactionStatus__c
      );
      System.assertEquals(
        InvoiceTransactionStatusService.organizationToday(),
        confirmedInvoice.SystemIntegrationDate__c,
        'Core 第7.9節・日付仕様 第8章: 確定日は組織タイムゾーンの操作日'
      );
      Set<Id> documentIds = new Set<Id>();
      for (ContentDocumentLink link : [
        SELECT ContentDocumentId
        FROM ContentDocumentLink
        WHERE LinkedEntityId = :invoice.Id
      ]) {
        documentIds.add(link.ContentDocumentId);
      }
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM ContentVersion
          WHERE
            ContentDocumentId IN :documentIds
            AND IsLatest = true
            AND ContractDocumentIssued__c = true
        ],
        'Core 第7.10節: 確定ではPDFを付けない'
      );
    }
  }

  @IsTest
  static void confirmInvoiceFromPreview_unusedDoesNotIssuePdf() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.InvoiceSendMode__c = 'Unused';
      update setting;
      ContractDocumentSettingService.clearCache();
      Invoice__c invoice = createInvoice(
        '未使用確定取引先',
        'Draft',
        'unused-confirm@example.com'
      );

      Test.startTest();
      InvoiceSendBoardController.ConfirmResultDto confirmed = InvoiceSendBoardController.confirmInvoiceFromPreview(
        invoice.Id,
        Date.today(),
        currentToken(invoice.Id)
      );
      Test.stopTest();

      System.assertEquals(1, confirmed.confirmedCount);
      System.assertEquals(null, confirmed.issueWarning);
      System.assertEquals(
        InvoiceTransactionStatusService.TX_CONFIRMED,
        [
          SELECT InvoiceTransactionStatus__c
          FROM Invoice__c
          WHERE Id = :invoice.Id
        ]
        .InvoiceTransactionStatus__c
      );
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM ContentDocumentLink
          WHERE LinkedEntityId = :invoice.Id
        ],
        'Core 第4.10節: 使わないなら確定の続きでPDFを付けない'
      );
    }
  }

  @IsTest
  static void confirmInvoiceFromPreview_doesNotIssueWhenCompanyNameEmpty() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.CompanyName__c = null;
      update setting;
      ContractDocumentSettingService.clearCache();
      Invoice__c invoice = createInvoice(
        '発行失敗確定取引先',
        'Draft',
        'issue-fail@example.com'
      );

      Test.startTest();
      InvoiceSendBoardController.ConfirmResultDto confirmed = InvoiceSendBoardController.confirmInvoiceFromPreview(
        invoice.Id,
        Date.today(),
        currentToken(invoice.Id)
      );
      Test.stopTest();

      System.assertEquals(1, confirmed.confirmedCount);
      System.assertEquals(
        null,
        confirmed.issueWarning,
        'Core 第7.10節: 確定はPDFを付けない'
      );
      System.assertEquals(
        InvoiceTransactionStatusService.TX_CONFIRMED,
        [
          SELECT InvoiceTransactionStatus__c
          FROM Invoice__c
          WHERE Id = :invoice.Id
        ]
        .InvoiceTransactionStatus__c,
        'Core 第7.9節・第11.3.1節: 会社情報空でも確定は止めない'
      );
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM ContentDocumentLink
          WHERE LinkedEntityId = :invoice.Id
        ],
        'Core 第7.10節: 確定ではPDFは付けない'
      );
    }
  }

  @IsTest
  static void getBoardContext_initialSelectionUsesCatalogDefault() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      InvoiceSendBoardController.BoardContextDto context = InvoiceSendBoardController.getBoardContext();
      System.assertEquals(
        'StandardInvoice',
        context.defaultDocumentTemplateKey,
        'Core 第11.3.2節: 有効な既定がちょうど1つなら初期選択'
      );
    }
  }

  @IsTest
  static void getBoardContext_reusesOrgSettingAndCatalogsInSameRequest() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      InvoiceSendBoardController.getBoardContext();
      Integer before = Limits.getQueries();
      InvoiceSendBoardController.BoardContextDto context = InvoiceSendBoardController.getBoardContext();
      System.assertEquals(
        before,
        Limits.getQueries(),
        'Core 第4.3.11節: 同一取得で組織設定と帳票・メールカタログを取り直さない'
      );
      System.assertEquals('StandardInvoice', context.defaultDocumentTemplateKey);
    }
  }

  @IsTest
  static void getBoardContext_returnsCompanyBlockedReasonWhenCompanyNameEmpty() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.CompanyName__c = null;
      update setting;
      ContractDocumentSettingService.clearCache();

      InvoiceSendBoardController.BoardContextDto context = InvoiceSendBoardController.getBoardContext();
      System.assertEquals(
        ContractDocumentSettingService.withDocumentSendHeading(
          ContractDocumentSettingService.MISSING_COMPANY_NAME_MESSAGE
        ),
        context.companyBlockedReason,
        'Core 第11.3.1節・第7.10節: 会社名空なら発行を止める理由に見出し名を付ける'
      );
    }
  }

  @IsTest
  static void getBoardContext_orgFromResolvedFalseWhenInvoiceOrgWideEmpty() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.InvoiceOrgWideEmailAddress__c = null;
      update setting;
      ContractDocumentSettingService.clearCache();

      InvoiceSendBoardController.BoardContextDto context = InvoiceSendBoardController.getBoardContext();
      System.assertEquals(
        false,
        context.orgFromResolved,
        'Core 第11.3.2節・第7.10節: 請求用組織送信元が空なら未解決'
      );
    }
  }

  private static Invoice__c createInvoice(
    String accountName,
    String collectionStatus,
    String toAddress
  ) {
    Account account = ContractTestDataFactory.insertAccount(accountName);
    BillingAccount__c billing = new BillingAccount__c(
      Account__c = account.Id,
      BillingAddressee__c = accountName + ' 御中',
      BillingEmailTo__c = toAddress == null ? 'source@example.com' : toAddress,
      BillingEmailCc__c = 'cc@example.com',
      BillingEmailBcc__c = 'bcc@example.com',
      InvoiceDeliveryMethod__c = InvoiceDeliveryMethodService.EMAIL,
      InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER,
      InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY,
      InvoiceDateDayOfMonth__c = 25,
      InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
      PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET,
      PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END,
      PaymentTermMonthOffset__c = 0,
      PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE);
    ContractTestDataFactory.applyRequiredFields(billing);
    insert billing;

    ContractService__c service = new ContractService__c(
      Name = accountName + ' サービス',
      Account__c = account.Id,
      BiilingAcccount__c = billing.Id,
      TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
    );
    ContractTestDataFactory.applyRequiredFields(service);
    insert service;

    ContractHistory__c history = new ContractHistory__c(
      Name = 'INV-SEND-HISTORY-' +
        String.valueOf(Crypto.getRandomInteger()).replace('-', ''),
      ContractService__c = service.Id,
      Type__c = 'New',
      historystatus__c = 'Estimate',
      Version__c = 1,
      CurrentTermStartDate__c = Date.today(),
      CurrentTermEndDate__c = Date.today().addYears(1).addDays(-1),
      EffectiveDate__c = Date.today()
    );
    ContractTestDataFactory.applyRequiredFields(history);
    ContractTestDataFactory.applyEstimateOrderedOpportunity(history, account.Id);
    insert history;

    Product2 product = ContractTestDataFactory.buildProduct(
      accountName + ' Prod ' + String.valueOf(Crypto.getRandomInteger())
    );
    product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
    ContractTestDataFactory.insertProduct(product);
    ContractProduct__c contractProduct = new ContractProduct__c(
      ContractHistory__c = history.Id,
      Account__c = account.Id,
      Product__c = product.Id,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME,
      Type__c = 'New',
      Quantity__c = 1,
      UnitPrice__c = 1000,
      Amount__c = 1000,
      StartDate__c = Date.today(),
      Enddate__c = Date.today().addYears(1).addDays(-1),
      RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME
    );
    ContractTestDataFactory.applyRequiredFields(contractProduct);
    contractProduct.Amount__c = 1000;
    insert contractProduct;
    history.historystatus__c = 'Ordered';
    update history;

    List<Invoice__c> generated = [
      SELECT Id, ContractHistory__c, ContractService__c
      FROM Invoice__c
      WHERE
        ContractHistory__c = :history.Id
        AND InvoiceTransactionStatus__c != :InvoiceTransactionStatusService.TX_CANCELLED
    ];
    Invoice__c invoice;
    if (!generated.isEmpty()) {
      invoice = generated[0];
      invoice.BillingEmailToSnapShot__c = toAddress == null
        ? ';'
        : toAddress;
      invoice.InvoiceDeliveryMethodSnapShot__c = InvoiceDeliveryMethodService.EMAIL;
      if (collectionStatus == 'Draft') {
        invoice.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_DRAFT;
        invoice.SystemIntegrationDate__c = null;
      } else {
        invoice.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED;
        invoice.SystemIntegrationDate__c = Date.today();
      }
      Boolean previous = InvoiceTransactionStatusService.allowStatusWrite;
      InvoiceTransactionStatusService.allowStatusWrite = true;
      try {
        update invoice;
      } finally {
        InvoiceTransactionStatusService.allowStatusWrite = previous;
      }
      return invoice;
    }

    history = [
      SELECT DeltaAmountSum__c
      FROM ContractHistory__c
      WHERE Id = :history.Id
    ];
    Decimal estimateExcl = history.DeltaAmountSum__c == null
      ? 0
      : history.DeltaAmountSum__c;
    invoice = new Invoice__c(
      ContractService__c = service.Id,
      ContractHistory__c = history.Id,
      InvoiceDate__c = Date.today(),
      PaymentScheduledDate__c = Date.today().addDays(30),
      Amount__c = estimateExcl,
      TaxAmount__c = TaxCalculationUtil.calculateTaxAmount(estimateExcl, 10),
      TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10),
      BillingAccountSnapShot__c = billing.Id,
      BillingAddresseeSnapShot__c = accountName + ' 御中',
      BillingEmailToSnapShot__c = toAddress == null ? ';' : toAddress,
      BillingEmailCcSnapShot__c = 'cc@example.com',
      BillingEmailBccSnapShot__c = 'bcc@example.com',
      InvoiceDeliveryMethodSnapShot__c = InvoiceDeliveryMethodService.EMAIL
    );
    ContractTestDataFactory.applyRequiredFields(invoice);
    ContractTestDataFactory.applyInvoiceInsertSeedStatuses(invoice);
    if (collectionStatus == 'Draft') {
      invoice.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_DRAFT;
    } else {
      invoice.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED;
      invoice.SystemIntegrationDate__c = Date.today();
    }
    ContractTestDataFactory.insertAllowingInvoiceStatus(invoice);
    InvoiceLine__c invoiceLine = new InvoiceLine__c(
      Invoice__c = invoice.Id,
      Amount__c = estimateExcl
    );
    ContractTestDataFactory.applyRequiredFields(invoiceLine);
    insert invoiceLine;
    return invoice;
  }

  @IsTest
  static void confirmInvoiceFromPreview_rejectsZeroAmountEmptyTaxPercent() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = createInvoice(
        '税抜0税率空取引先',
        'Draft',
        'zero-tax@example.com'
      );
      invoice.Amount__c = 0;
      invoice.TaxAmount__c = 0;
      invoice.TaxPercent__c = null;
      update invoice;
      ContractHistory__c history = [
        SELECT Id
        FROM ContractHistory__c
        WHERE Id = :invoice.ContractHistory__c
      ];
      history.DeltaAmountSum__c = 0;
      update history;
      Boolean rejected = false;
      Test.startTest();
      try {
        InvoiceSendBoardController.confirmInvoiceFromPreview(
          invoice.Id,
          Date.today(),
          currentToken(invoice.Id),
          null,
          invoice.ContractHistory__c
        );
      } catch (Exception ex) {
        rejected = true;
        System.assert(
          ex.getMessage().contains('空'),
          'Core 第7.4節・第7.9.1節: 税抜0でも税率空は確定しない。実際: ' +
            ex.getMessage()
        );
      }
      Test.stopTest();
      System.assertEquals(true, rejected);
      System.assertEquals(
        InvoiceTransactionStatusService.TX_DRAFT,
        [
          SELECT InvoiceTransactionStatus__c
          FROM Invoice__c
          WHERE Id = :invoice.Id
        ]
        .InvoiceTransactionStatus__c,
        'Core 第7.4節: 税率空の確定は通さない'
      );
    }
  }

  @IsTest
  static void confirmInvoiceFromPreview_withoutLoop11_rejectsNonDraftWithStatus() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = createInvoice(
        '確定11無し状態取引先',
        'Confirmed',
        'no-loop11-status@example.com'
      );
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.CONFIRM_INVOICE => false
      };
      Boolean rejected = false;
      try {
        Test.startTest();
        InvoiceSendBoardController.confirmInvoiceFromPreview(
          invoice.Id,
          Date.today(),
          currentToken(invoice.Id),
          null,
          invoice.ContractHistory__c
        );
      } catch (AuraHandledException ex) {
        rejected = true;
        System.assert(
          ex.getMessage().contains('未確定の請求のみ確定できます'),
          '共通基盤第3.8節: Loop_11無しでも未確定でない請求は状態エラー。実際: ' +
            ex.getMessage()
        );
        System.assert(
          !ex.getMessage().contains('権限がありません'),
          '共通基盤第3.8節: 状態不足と権限不足を分けない'
        );
      } finally {
        ContractPermissionUtil.testOverrides = null;
        Test.stopTest();
      }
      System.assertEquals(true, rejected);
    }
  }

  @IsTest
  static void confirmInvoiceFromPreview_withoutLoop11_rejectsDraftWithPermission() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = createInvoice(
        '未確定11無し権限取引先',
        'Draft',
        'no-loop11-perm@example.com'
      );
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.CONFIRM_INVOICE => false
      };
      Boolean rejected = false;
      try {
        Test.startTest();
        InvoiceSendBoardController.confirmInvoiceFromPreview(
          invoice.Id,
          Date.today(),
          currentToken(invoice.Id),
          null,
          invoice.ContractHistory__c
        );
      } catch (AuraHandledException ex) {
        rejected = true;
        System.assertEquals(
          '請求を確定する権限がありません。',
          ex.getMessage(),
          '共通基盤第3.1節: 確定そのものは Loop_11。実際: ' + ex.getMessage()
        );
      } finally {
        ContractPermissionUtil.testOverrides = null;
        Test.stopTest();
      }
      System.assertEquals(true, rejected);
    }
  }

  @IsTest
  static void confirmInvoiceFromPreview_rejectsConfirmedInvoice() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = createInvoice(
        '確定済拒否取引先',
        'Confirmed',
        'already-confirmed@example.com'
      );
      Boolean rejected = false;
      Test.startTest();
      try {
        InvoiceSendBoardController.confirmInvoiceFromPreview(
          invoice.Id,
          Date.today(),
          currentToken(invoice.Id)
        );
      } catch (AuraHandledException ex) {
        rejected = true;
        System.assert(
          ex.getMessage().contains('未確定の請求のみ確定できます'),
          'Core 第7.9節: 未確定の請求のみ確定できる'
        );
      }
      Test.stopTest();
      System.assertEquals(true, rejected);
    }
  }

  @IsTest
  static void confirmInvoiceFromPreview_sameKeyDoesNotConfirmTwice() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = createInvoice(
        '確定キー再試行取引先',
        'Draft',
        'confirm-retry@example.com'
      );
      String token = currentToken(invoice.Id);
      Test.startTest();
      InvoiceSendBoardController.ConfirmResultDto first = InvoiceSendBoardController.confirmInvoiceFromPreview(
        invoice.Id,
        Date.today(),
        token,
        null
      );
      InvoiceSendBoardController.ConfirmResultDto retry = InvoiceSendBoardController.confirmInvoiceFromPreview(
        invoice.Id,
        Date.today(),
        token,
        first.businessOperationKey
      );
      Test.stopTest();
      System.assertEquals(
        1,
        retry.confirmedCount,
        'Core 第7.9.7節: 同じキーの再試行は1件のまま'
      );
      System.assertEquals(
        first.businessOperationKey,
        retry.businessOperationKey
      );
    }
  }

  @IsTest
  static void confirmInvoiceFromPreview_reusesLockedInvoiceVersionCheck() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = createInvoice(
        '確定版再利用取引先',
        'Draft',
        'confirm-reuse@example.com'
      );
      Invoice__c locked = AccountingCauseLockService.lockInvoice(invoice.Id);
      String expectedToken = ContractOptimisticLockUtil.toToken(
        AccountingCauseLockService.resolveInvoiceOperationDatetimes(
            new Set<Id>{ locked.Id },
            new Map<Id, Datetime>{ locked.Id => locked.LastModifiedDate }
          )
          .get(locked.Id)
      );
      Integer beforeKnown = Limits.getQueries();
      AccountingCauseLockService.assertInvoiceOperationUnchanged(
        locked.Id,
        expectedToken,
        locked.LastModifiedDate
      );
      Integer usedKnown = Limits.getQueries() - beforeKnown;
      Integer beforeFull = Limits.getQueries();
      AccountingCauseLockService.assertInvoiceOperationUnchanged(
        locked.Id,
        expectedToken
      );
      Integer usedFull = Limits.getQueries() - beforeFull;
      System.assert(
        usedKnown < usedFull,
        'Core 第12.4節・第7.9.7節: 確定はロック済み請求の版比較を取り直さない'
      );
    }
  }

  @IsTest
  static void confirmInvoiceFromPreview_reusesLockCurrentCopyAndEstimate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = createInvoice(
        '確定収集再利用',
        'Draft',
        'confirm-collect@example.com'
      );
      invoice = [
        SELECT Id, ContractHistory__c, LastModifiedDate
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      InvoiceOpsController.lastEstimateMatchQueriedIds = new Set<Id>();
      String expectedToken = currentToken(invoice.Id);
      AccountingCauseLockService.invoiceModifiedSelectCount = 0;
      AccountingCurrentService.currentLoadSelectCount = 0;
      AccountingDiffService.invoiceCopySourceSelectCount = 0;
      AccountingGoalService.allocationLoadSelectCount = 0;
      AccountingGoalService.lineLoadSelectCount = 0;
      Test.startTest();
      InvoiceSendBoardController.ConfirmResultDto confirmed = InvoiceSendBoardController.confirmInvoiceFromPreview(
        invoice.Id,
        Date.today(),
        expectedToken,
        null,
        invoice.ContractHistory__c
      );
      Test.stopTest();
      System.assertEquals(1, confirmed.confirmedCount);
      System.assertEquals(
        0,
        AccountingCauseLockService.invoiceModifiedSelectCount,
        'Core 第7.9.7節: ロック済み請求の更新日時は取り直さない'
      );
      System.assertEquals(
        1,
        AccountingCurrentService.currentLoadSelectCount,
        'Accounting 第8.2節: 版比較のCurrentをapplyが取り直さない'
      );
      System.assertEquals(
        false,
        InvoiceOpsController.lastEstimateMatchQueriedIds.contains(invoice.Id),
        'Core 第7.9.1節: ロック済み請求の税抜・税額は取り直さない'
      );
      System.assertEquals(
        0,
        AccountingDiffService.invoiceCopySourceSelectCount,
        'Core 第11.4.2節: コピーFromはGoal収集を使い取り直さない'
      );
      System.assertEquals(
        0,
        AccountingGoalService.allocationLoadSelectCount,
        'Accounting 第8.4節: 確定時点にInvoice入金が無くても割当を取り直さない'
      );
      System.assertEquals(
        1,
        AccountingGoalService.lineLoadSelectCount,
        'Accounting 第8.2節: collectLinesした明細をapplyが取り直さない'
      );
      InvoiceLine__c persisted = [
        SELECT AllocatedTaxAmount__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :invoice.Id
        LIMIT 1
      ];
      InvoiceLine__c collected = AccountingGoalService.collectedLines(
          invoice.Id
        )
        .get(persisted.Id);
      System.assertNotEquals(
        null,
        collected,
        'Accounting 第8.2節: 確定で集めた明細を残す'
      );
      System.assertEquals(
        persisted.AllocatedTaxAmount__c,
        collected.AllocatedTaxAmount__c,
        'Core 第7.4節・Accounting 第8.4節: Goalの明細は配分後の税額'
      );
    }
  }

  @IsTest
  static void confirmInvoiceFromPreview_rejectsInvoiceOutsideContractService() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c own = createInvoice(
        '確定所属Own',
        'Draft',
        'confirm-own@example.com'
      );
      Test.startTest();
      Invoice__c other = createInvoice(
        '確定所属Other',
        'Draft',
        'confirm-other@example.com'
      );

      Boolean rejected = false;
      try {
        InvoiceSendBoardController.confirmInvoiceFromPreview(
          other.Id,
          Date.today(),
          currentToken(other.Id),
          null,
          own.ContractHistory__c
        );
      } catch (AuraHandledException ex) {
        rejected = true;
        System.assertEquals(
          InvoiceOpsController.SCOPE_MISMATCH_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(
        true,
        rejected,
        'Core 第7.7.3節: 開いている契約サービス以外の請求は確定できない'
      );
      System.assertEquals(
        InvoiceTransactionStatusService.TX_DRAFT,
        [
          SELECT InvoiceTransactionStatus__c
          FROM Invoice__c
          WHERE Id = :other.Id
        ]
        .InvoiceTransactionStatus__c
      );
      Test.stopTest();
    }
  }

  private static String currentToken(Id invoiceId) {
    return AccountingCauseLockService.resolveInvoiceOperationToken(invoiceId);
  }
}
