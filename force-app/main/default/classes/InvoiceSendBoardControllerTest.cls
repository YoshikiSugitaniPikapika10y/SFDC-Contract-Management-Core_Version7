@IsTest
private class InvoiceSendBoardControllerTest {
  @TestSetup
  static void setup() {
    ContractTestDataFactory.initTestContext();
    ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
    setting.InvoiceSendMode__c = 'PdfAndEmail';
    setting.InvoiceDefaultDocumentTemplateKey__c = 'StandardInvoice';
    setting.InvoiceDefaultEmailTemplateApiName__c = 'InvoiceMail';
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
      createInvoice('Draft取引先', 'Draft', 'draft@example.com');

      Test.startTest();
      InvoiceSendBoardController.BoardContextDto context = InvoiceSendBoardController.getBoardContext();
      System.assertEquals(true, context.canSend);
      System.assertEquals(true, context.featureEnabled);
      System.assertEquals(500, context.listLimit);
      System.assertEquals('StandardInvoice', context.defaultDocumentTemplateKey);
      System.assert(
        !context.documentTemplateOptions.isEmpty(),
        'Invoice帳票テンプレートが返ること'
      );

      Test.stopTest();
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
        'Core 第7.10節: 確定成功の続きで既定帳票PDFを付ける'
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
        1,
        [
          SELECT COUNT()
          FROM ContentVersion
          WHERE
            ContentDocumentId IN :documentIds
            AND IsLatest = true
            AND ContractDocumentIssued__c = true
        ],
        'Core 第7.9節: 確定成功の続きで既定帳票PDFを1つ付ける'
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
  static void confirmInvoiceFromPreview_keepsConfirmWhenIssueFails() {
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
      System.assertNotEquals(
        null,
        confirmed.issueWarning,
        'Core 第7.10節: 発行できなかった理由を返す'
      );
      System.assertEquals(
        InvoiceTransactionStatusService.TX_CONFIRMED,
        [
          SELECT InvoiceTransactionStatus__c
          FROM Invoice__c
          WHERE Id = :invoice.Id
        ]
        .InvoiceTransactionStatus__c,
        'Core 第7.9節: 発行できないときは確定を戻さない'
      );
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM ContentDocumentLink
          WHERE LinkedEntityId = :invoice.Id
        ],
        'Core 第7.10節: 発行できないときはPDFは付けない'
      );
    }
  }

  @IsTest
  static void getBoardContext_doesNotFillEmptyDefaultDocumentKey() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.InvoiceDefaultDocumentTemplateKey__c = null;
      update setting;
      ContractDocumentSettingService.clearCache();

      InvoiceSendBoardController.BoardContextDto context = InvoiceSendBoardController.getBoardContext();
      System.assertEquals(
        null,
        context.defaultDocumentTemplateKey,
        'Core 第11.3.2節・第1.1.10節: 既定帳票が空ならカタログ先頭で埋めない'
      );
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
        ContractDocumentSettingService.MISSING_COMPANY_NAME_MESSAGE,
        context.companyBlockedReason,
        'Core 第11.3.1節・第7.10節: 会社名空なら発行を止める理由を返す'
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
      historystatus__c = 'Ordered',
      Version__c = 1,
      CurrentTermStartDate__c = Date.today(),
      CurrentTermEndDate__c = Date.today().addYears(1).addDays(-1)
    );
    ContractTestDataFactory.applyRequiredFields(history);
    insert history;

    // DeltaAmountSum__c（発生金額）は契約商品 Amount のロールアップ。
    // 確定ガードは見積合計＝請求合計（税抜）を要求するため、請求 Amount と同額を置く。
    Product2 product = ContractTestDataFactory.buildProduct(
      accountName + ' Prod'
    );
    product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
    ContractTestDataFactory.insertProduct(product);
    ContractProduct__c contractProduct = new ContractProduct__c(
      ContractHistory__c = history.Id,
      Account__c = account.Id,
      Product__c = product.Id,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      Amount__c = 1000,
      StartDate__c = Date.today(),
      Enddate__c = Date.today().addYears(1).addDays(-1)
    );
    ContractTestDataFactory.applyRequiredFields(contractProduct);
    insert contractProduct;

    Invoice__c invoice = new Invoice__c(
      ContractService__c = service.Id,
      ContractHistory__c = history.Id,
      InvoiceDate__c = Date.today(),
      PaymentScheduledDate__c = Date.today().addDays(30),
      Amount__c = 1000,
      TaxAmount__c = 100,
      TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10),
      InvoiceTransactionStatus__c = collectionStatus == 'Draft'
        ? InvoiceTransactionStatusService.TX_DRAFT
        : InvoiceTransactionStatusService.TX_CONFIRMED,
      SystemIntegrationDate__c = collectionStatus == 'Draft'
        ? null
        : Date.today(),
      BillingAccountSnapShot__c = billing.Id,
      BillingAddresseeSnapShot__c = accountName + ' 御中',
      BillingEmailToSnapShot__c = toAddress == null ? ';' : toAddress,
      BillingEmailCcSnapShot__c = 'cc@example.com',
      BillingEmailBccSnapShot__c = 'bcc@example.com',
      InvoiceDeliveryMethodSnapShot__c = InvoiceDeliveryMethodService.EMAIL
    );
    ContractTestDataFactory.applyRequiredFields(invoice);
    ContractTestDataFactory.insertAllowingInvoiceStatus(invoice);
    insert new InvoiceLine__c(Invoice__c = invoice.Id, Amount__c = 1000);
    return invoice;
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
  static void confirmInvoiceFromPreview_rejectsInvoiceOutsideContractService() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c own = createInvoice(
        '確定所属Own',
        'Draft',
        'confirm-own@example.com'
      );
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
    }
  }

  private static String currentToken(Id invoiceId) {
    return AccountingCauseLockService.resolveInvoiceOperationToken(invoiceId);
  }
}
