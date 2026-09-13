@IsTest
private class InvoiceDocumentServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
    ContractTestDataFactory.ensureOrgAccountingPolicy();
  }

  @IsTest
  static void loadContext_usesInvoiceSnapshotsAndDefaultOrgSetting() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('Confirmed');

      InvoiceDocumentService.DocumentContext context = InvoiceDocumentService.loadContext(
        fixture.invoice.Id
      );

      System.assertEquals(
        '帳票取引先 請求担当',
        context.addressee,
        'Core 第7.10節: 宛名は請求書スナップショット。マスタ宛名では埋めない'
      );
      System.assertEquals(
        '2026年06月30日',
        context.invoiceDateLabel,
        'Core 第7.10節・日付仕様 第8章: 請求日は保存値だけを印字する'
      );
      System.assertEquals(
        '2026年07月31日',
        context.paymentDueDateLabel,
        'Core 第7.10節・日付仕様 第8章: 入金予定日は保存値だけを印字する'
      );
      System.assertEquals(
        10000,
        context.amountExcludingTax,
        'Core 第7.10節: 請求PDFの税抜は請求書の税抜'
      );
      System.assertEquals(
        1000,
        context.taxAmount,
        'Core 第7.10節: 請求PDFの税額は請求書の税額'
      );
      System.assertEquals(
        11000,
        context.amountIncludingTax,
        'Core 第7.10節: 請求PDFの税込は請求書の税込'
      );
      System.assertEquals(1, context.lines.size());
      System.assertEquals(
        'スナップショット商品',
        context.lines[0].ProductName__c,
        'Core 第7.10節: 明細の商品名は請求明細のスナップショット'
      );
      System.assertEquals(
        '2026年6月分',
        context.lines[0].PeriodLabel__c,
        'Core 第7.10節: 明細の期間ラベルは請求明細の値'
      );
      System.assertEquals(
        '帳票発行株式会社',
        context.documentSetting.CompanyName__c,
        'Core 第11.3.1節: 会社名は組織設定の帳票'
      );
      System.assertEquals(
        'T1234567890123',
        context.documentSetting.InvoiceRegistrationNumber__c,
        'Core 第11.3.1節: 適格請求書発行事業者登録番号は組織設定'
      );
      System.assertEquals(
        '振込手数料は貴社にてご負担ください。',
        context.documentSetting.DocumentFooter__c,
        'Core 第11.3.1節: 帳票フッターは空でなければ請求PDFへ出す'
      );
      System.assertEquals(
        'https://example.com/privacy',
        context.documentSetting.PrivacyPolicyUrl__c,
        'Core 第11.3.1節: プライバシーポリシーURLは空でなければ請求PDFへ出す'
      );
    }
  }

  @IsTest
  static void loadContext_reusesKnownInvoiceWithoutSecondHeaderQuery() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('Confirmed');
      InvoiceDocumentService.DocumentContext first = InvoiceDocumentService.loadContext(
        fixture.invoice.Id
      );
      Integer afterFirst = Limits.getQueries();
      InvoiceDocumentService.DocumentContext second = InvoiceDocumentService.loadContext(
        fixture.invoice.Id,
        first.invoice
      );
      System.assertEquals(
        first.amountExcludingTax,
        second.amountExcludingTax,
        'Core 第12.4節: ロック済み請求の発行結果は変えない'
      );
      System.assert(
        Limits.getQueries() - afterFirst < afterFirst,
        'Core 第12.4節: 同一処理でロック済み請求を取り直さない'
      );
    }
  }

  @IsTest
  static void loadContext_draftInvoiceIsRejected() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('Draft');
      Boolean thrown = false;

      try {
        InvoiceDocumentService.loadContext(fixture.invoice.Id);
      } catch (InvoiceDocumentService.InvoiceDocumentException ex) {
        thrown = true;
        System.assertEquals(
          InvoiceDocumentService.STATUS_REQUIRED_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown, 'Draft の直接PDF表示も拒否すること');
      System.assertEquals(
        '請求書の表示・発行は請求取引状態が確定済みの請求のみ利用できます。',
        InvoiceDocumentService.STATUS_REQUIRED_MESSAGE,
        'Core 第0.1節・第7.10節・第7.11節: 拒否は請求取引状態の確定済み。回収ステータスや Confirmed は出さない'
      );
    }
  }

  @IsTest
  static void buildFileName_nullInvoiceDate_usesOrganizationToday() {
    Date orgToday = InvoiceTransactionStatusService.organizationToday();
    String compact =
      String.valueOf(orgToday.year()) +
      String.valueOf(orgToday.month()).leftPad(2, '0') +
      String.valueOf(orgToday.day()).leftPad(2, '0');
    Invoice__c invoice = new Invoice__c();

    String fileName = InvoiceDocumentService.buildFileName(invoice, null);

    System.assertEquals(
      'Invoice_請求書_' + compact + '.pdf',
      fileName,
      '日付仕様 第8章: 請求日未設定のファイル名の今日は組織タイムゾーン。宛名空は請求書'
    );
  }

  @IsTest
  static void issueInvoiceDocument_usesCmdtAndLinksTestPdf() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('Confirmed');

      Test.startTest();
      InvoiceDocumentService.IssueResult result = InvoiceDocumentService.issueInvoiceDocument(
        fixture.invoice.Id,
        'StandardInvoice'
      );
      Test.stopTest();

      System.assertNotEquals(
        null,
        result.contentVersionId,
        'Core 第7.10節: 発行は標準Filesへ保存する'
      );
      System.assertNotEquals(
        null,
        result.contentDocumentId,
        'Core 第7.10節: 発行結果は ContentDocument を返す'
      );
      System.assertEquals(
        'StandardInvoice',
        result.templateKey,
        'Core 第7.10節・第11.3.2節: 人が選んだ帳票キーを返す'
      );
      System.assertEquals(
        'InvoiceDocumentPdf',
        result.visualforcePage,
        'Core 第11.3.2節: 帳票カタログの Visualforce を使う'
      );
      System.assertEquals(
        'StandardInvoice_帳票取引先_請求担当_20260630.pdf',
        result.fileName,
        'Core 第11.3.2節: 請求の {Title} は宛名スナップショット'
      );
      ContentVersion saved = [
        SELECT Title, PathOnClient, VersionData, ContractDocumentIssued__c
        FROM ContentVersion
        WHERE Id = :result.contentVersionId
      ];
      System.assertEquals(
        true,
        saved.ContractDocumentIssued__c,
        'Core 第4.8節・第7.10節: 発行 insert に印を付ける'
      );
      System.assertEquals(
        'StandardInvoice_帳票取引先_請求担当_20260630.pdf',
        saved.PathOnClient,
        'Core 第11.3.2節: 請求の {Title} は宛名スナップショット'
      );
      System.assertEquals(
        Blob.valueOf('%PDF-1.4 invoice test').toString(),
        saved.VersionData.toString(),
        'テスト実行中の発行本文はダミーPDF'
      );
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM ContentDocumentLink
          WHERE LinkedEntityId = :fixture.invoice.Id
        ],
        'Core 第7.10節: 請求の発行PDFの保存先は請求書の標準Files'
      );
    }
  }

  @IsTest
  static void issueInvoiceDocument_unusedMode_throwsExactMessage() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.InvoiceSendMode__c = ContractDocumentSettingService.MODE_UNUSED;
      update setting;
      ContractDocumentSettingService.clearCache();
      Fixture fixture = createFixture('Confirmed');
      Boolean thrown = false;

      try {
        InvoiceDocumentService.issueInvoiceDocument(
          fixture.invoice.Id,
          'StandardInvoice'
        );
      } catch (InvoiceDocumentService.InvoiceDocumentException ex) {
        thrown = true;
        System.assertEquals(
          '請求書設定が使わないのため、発行も送付もできません。',
          ex.getMessage(),
          'Core 第7.10節: 使わないなら発行も送付もしない'
        );
      }
      System.assertEquals(
        true,
        thrown,
        'Core 第7.10節: 使わないなら発行を止める'
      );
    }
  }

  @IsTest
  static void issueInvoiceDocument_usesAttachmentFileName() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('Confirmed');

      Test.startTest();
      InvoiceDocumentService.IssueResult result = InvoiceDocumentService.issueInvoiceDocument(
        fixture.invoice.Id,
        'StandardInvoice',
        '送付添付_請求書.pdf'
      );
      Test.stopTest();

      System.assertEquals(
        '送付添付_請求書.pdf',
        result.fileName,
        'Core 第7.10節: 新しく発行するの送付添付名はその送付だけ直せる'
      );
      ContentVersion saved = [
        SELECT Title, PathOnClient, ContractDocumentIssued__c
        FROM ContentVersion
        WHERE Id = :result.contentVersionId
      ];
      System.assertEquals(
        true,
        saved.ContractDocumentIssued__c,
        'Core 第7.10節: 新しく発行するでも印を付ける'
      );
      System.assertEquals(
        '送付添付_請求書.pdf',
        saved.PathOnClient,
        'Core 第7.10節: 新しく発行するの Files Title は送った添付名'
      );
      System.assertEquals(
        '送付添付_請求書',
        saved.Title,
        'Core 第7.10節: 新しく発行するの Title は添付名から .pdf を除いた値'
      );
    }
  }

  @IsTest
  static void loadContext_cancelledInvoiceIsRejected() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('Confirmed');
      Boolean previousStatus = InvoiceTransactionStatusService.allowStatusWrite;
      Boolean previousLock = InvoiceLockUtil.allowLockedStatusWrite;
      InvoiceTransactionStatusService.allowStatusWrite = true;
      InvoiceLockUtil.allowLockedStatusWrite = true;
      try {
        fixture.invoice.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CANCELLED;
        update fixture.invoice;
      } finally {
        InvoiceTransactionStatusService.allowStatusWrite = previousStatus;
        InvoiceLockUtil.allowLockedStatusWrite = previousLock;
      }
      Boolean thrown = false;

      try {
        InvoiceDocumentService.loadContext(fixture.invoice.Id);
      } catch (InvoiceDocumentService.InvoiceDocumentException ex) {
        thrown = true;
        System.assertEquals(
          InvoiceDocumentService.STATUS_REQUIRED_MESSAGE,
          ex.getMessage(),
          'Core 第7.10節: 取消済み請求は通常発行の対象にしない'
        );
      }
      System.assertEquals(
        true,
        thrown,
        'Core 第7.10節: 取消済みの表示・発行は拒否する'
      );
    }
  }

  @IsTest
  static void pdfController_bindsConfirmedInvoice() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('Confirmed');
      PageReference pageReference = Page.InvoiceDocumentPdf;
      pageReference.getParameters().put('id', fixture.invoice.Id);
      Test.setCurrentPage(pageReference);

      InvoiceDocumentPdfController controller = new InvoiceDocumentPdfController();

      System.assertEquals(
        true,
        controller.hasContext,
        'Core 第7.10節: 確定済み請求のPDF表示はコンテキストを載せる'
      );
      System.assertEquals(
        fixture.invoice.Id,
        controller.context.invoice.Id,
        'Core 第7.10節: PDF表示は当該請求書のスナップショット'
      );
      System.assertEquals(
        1,
        controller.context.lines.size(),
        'Core 第7.10節: 請求PDFの明細は請求明細'
      );
      System.assertEquals(
        '帳票取引先 請求担当',
        controller.context.addressee,
        'Core 第7.10節: PDF宛名は請求書スナップショット'
      );
    }
  }

  @IsTest
  static void pdfController_handlesMissingInvalidAndDraftIds() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Test.setCurrentPage(Page.InvoiceDocumentPdf);
      InvoiceDocumentPdfController missingController = new InvoiceDocumentPdfController();
      System.assertEquals(
        false,
        missingController.hasContext,
        'Core 第7.10節: 請求IDが無い直接PDF表示はコンテキストを出さない'
      );

      ApexPages.currentPage().getParameters().put('id', 'invalid');
      InvoiceDocumentPdfController invalidController = new InvoiceDocumentPdfController();
      System.assertEquals(
        false,
        invalidController.hasContext,
        'Core 第7.10節: 無い請求の直接PDF表示はコンテキストを出さない'
      );

      Fixture draftFixture = createFixture('Draft');
      ApexPages.currentPage()
        .getParameters()
        .put('id', String.valueOf(draftFixture.invoice.Id));
      InvoiceDocumentPdfController draftController = new InvoiceDocumentPdfController();
      System.assertEquals(false, draftController.hasContext);
      System.assertEquals(1, ApexPages.getMessages().size());
      System.assertEquals(
        InvoiceDocumentService.STATUS_REQUIRED_MESSAGE,
        ApexPages.getMessages()[0].getSummary(),
        'Core 第7.10節: Draft の直接PDFは拒否文を出す'
      );
    }
  }

  @IsTest
  static void loadContext_andSavePdf_rejectBlankIdsAndEmptyBody() {
    Boolean missingId = false;
    try {
      InvoiceDocumentService.loadContext(null);
    } catch (InvoiceDocumentService.InvoiceDocumentException ex) {
      missingId = true;
      System.assertEquals(
        '請求IDが指定されていません。',
        ex.getMessage(),
        'Core 第7.10節: 請求IDが無い発行は止める'
      );
    }
    System.assertEquals(true, missingId);

    Boolean notFound = false;
    try {
      InvoiceDocumentService.loadContext(UserInfo.getUserId());
    } catch (InvoiceDocumentService.InvoiceDocumentException ex) {
      notFound = true;
      System.assertEquals(
        '請求が見つかりません。',
        ex.getMessage(),
        'Core 第7.10節: 無い請求は発行できない'
      );
    }
    System.assertEquals(true, notFound);

    Boolean missingSaveId = false;
    try {
      InvoiceDocumentService.savePdfToInvoice(
        null,
        'invoice.pdf',
        Blob.valueOf('%PDF-1.4')
      );
    } catch (InvoiceDocumentService.InvoiceDocumentException ex) {
      missingSaveId = true;
      System.assertEquals(
        '保存先の請求IDが指定されていません。',
        ex.getMessage(),
        'Core 第7.10節: 保存先の請求が無い発行は止める'
      );
    }
    System.assertEquals(true, missingSaveId);

    Boolean emptyPdf = false;
    try {
      InvoiceDocumentService.savePdfToInvoice(
        UserInfo.getUserId(),
        'invoice.pdf',
        null
      );
    } catch (InvoiceDocumentService.InvoiceDocumentException ex) {
      emptyPdf = true;
      System.assertEquals(
        'PDFデータが空です。',
        ex.getMessage(),
        'Core 第7.10節: 空のPDFは発行できない'
      );
    }
    System.assertEquals(true, emptyPdf);

    System.assertEquals(
      '請求書',
      InvoiceDocumentService.sanitizeFileName(null),
      'Core 第11.3.2節: 空のファイル名は請求書'
    );
    System.assertEquals(
      'a_b_c',
      InvoiceDocumentService.sanitizeFileName('a/b:c'),
      'Core 第11.3.2節: ファイル名の禁則文字は置き換える'
    );
    System.assertEquals(
      '',
      InvoiceDocumentService.formatDisplayDate(null),
      '日付仕様 第8章: 空の請求日は本文を今日で埋めない'
    );
  }

  @IsTest
  static void generatePdfBlob_returnsDummyDuringTest() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('Confirmed');
      Blob body = InvoiceDocumentService.generatePdfBlob(
        fixture.invoice.Id,
        'StandardInvoice'
      );
      System.assertEquals(
        Blob.valueOf('%PDF-1.4 invoice test').toString(),
        body.toString(),
        'テスト実行中はダミーPDF本文'
      );
    }
  }

  @IsTest
  static void issueInvoiceDocument_blankKey_throws() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('Confirmed');
      Boolean thrown = false;
      try {
        InvoiceDocumentService.issueInvoiceDocument(fixture.invoice.Id);
      } catch (InvoiceDocumentService.InvoiceDocumentException ex) {
        thrown = true;
        System.assertEquals(
          ContractDocumentSettingService.withDocumentSendHeading(
            ContractDocumentSettingService.MISSING_DEFAULT_DOCUMENT_MESSAGE
          ),
          ex.getMessage(),
          'Core 第7.10節・第11.3.2節: キー空は発行できない。既定印でもカタログ先頭でも埋めない'
        );
        System.assertEquals(
          '帳票・送付：PDFのみ／PDFとメール送付のとき、既定帳票を選んでください。',
          ex.getMessage(),
          'Core 第7.10節・第11.3.1節: 不足エラーは業務日本語に見出しを付ける'
        );
      }
      System.assertEquals(
        true,
        thrown,
        'Core 第7.10節: 帳票キーが空なら発行できない'
      );
    }
  }

  private class Fixture {
    Invoice__c invoice;
  }

  private static Fixture createFixture(String collectionStatus) {
    Account account = ContractTestDataFactory.insertAccount('帳票取引先');
    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = account.Id,
      BillingAddressee__c = 'マスタ宛名',
      BillingEmailTo__c = 'invoice@example.com',
      InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER,
      InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY,
      InvoiceDateDayOfMonth__c = 25,
      InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
      PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET,
      PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END,
      PaymentTermMonthOffset__c = 0,
      PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE
    );
    ContractTestDataFactory.applyRequiredFields(billingAccount);
    insert billingAccount;

    ContractService__c service = new ContractService__c(
      Name = 'Invoice Document Service',
      Account__c = account.Id,
      BiilingAcccount__c = billingAccount.Id,
      TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
    );
    ContractTestDataFactory.applyRequiredFields(service);
    insert service;

    ContractHistory__c history = new ContractHistory__c(
      Name = 'Invoice Document History',
      ContractService__c = service.Id,
      Type__c = 'New',
      historystatus__c = 'Estimate',
      Version__c = 1,
      CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
      CurrentTermEndDate__c = Date.newInstance(2026, 6, 30),
      EffectiveDate__c = Date.newInstance(2026, 6, 1)
    );
    ContractTestDataFactory.applyRequiredFields(history);
    ContractTestDataFactory.applyEstimateOrderedOpportunity(
      history,
      account.Id
    );
    insert history;
    Product2 product = ContractTestDataFactory.buildProduct(
      'Invoice Document Product ' + String.valueOf(Crypto.getRandomInteger())
    );
    product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
    ContractTestDataFactory.insertProduct(product);
    ContractProduct__c contractProduct = new ContractProduct__c(
      ContractHistory__c = history.Id,
      Account__c = account.Id,
      Product__c = product.Id,
      Quantity__c = 1,
      UnitPrice__c = 10000,
      Amount__c = 10000,
      StartDate__c = Date.newInstance(2026, 6, 1),
      Enddate__c = Date.newInstance(2026, 6, 30),
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME,
      Type__c = 'New',
      RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME
    );
    ContractTestDataFactory.applyRequiredFields(contractProduct);
    contractProduct.Amount__c = 10000;
    insert contractProduct;
    history.historystatus__c = 'Ordered';
    update history;

    Invoice__c invoice = new Invoice__c(
      ContractService__c = service.Id,
      ContractHistory__c = history.Id,
      InvoiceDate__c = Date.newInstance(2026, 6, 30),
      PaymentScheduledDate__c = Date.newInstance(2026, 7, 31),
      BillingAccountSnapShot__c = billingAccount.Id,
      BillingAddresseeSnapShot__c = '帳票取引先 請求担当',
      PaymentTermMethodSnapShot__c = BillingScheduleService.METHOD_MONTH_OFFSET,
      Amount__c = 10000,
      TaxAmount__c = 1000
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

    InvoiceLine__c line = new InvoiceLine__c(
      Invoice__c = invoice.Id,
      ProductName__c = 'スナップショット商品',
      ProductCodeSnapShot__c = 'SKU-001',
      PeriodLabel__c = '2026年6月分',
      Unit__c = '式',
      Quantity__c = 2,
      UnitPrice__c = 5000,
      Amount__c = 10000
    );
    ContractTestDataFactory.applyRequiredFields(line);
    insert line;

    ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
    setting.CompanyName__c = '帳票発行株式会社';
    setting.Address__c = '東京都千代田区1-1-1';
    setting.InvoiceRegistrationNumber__c = 'T1234567890123';
    setting.BankTransferInfo__c = 'テスト銀行 本店 普通 1234567';
    setting.DocumentFooter__c = '振込手数料は貴社にてご負担ください。';
    setting.PrivacyPolicyUrl__c = 'https://example.com/privacy';
    update setting;
    ContractDocumentSettingService.clearCache();

    Fixture fixture = new Fixture();
    fixture.invoice = invoice;
    return fixture;
  }
}
