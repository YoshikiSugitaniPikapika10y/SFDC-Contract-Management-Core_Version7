@IsTest
private class InvoiceDocumentServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void loadContext_usesInvoiceSnapshotsAndDefaultOrgSetting() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('Confirmed');

      InvoiceDocumentService.DocumentContext context =
        InvoiceDocumentService.loadContext(fixture.invoice.Id);

      System.assertEquals('帳票取引先 請求担当', context.addressee);
      System.assertEquals('2026年06月30日', context.invoiceDateLabel);
      System.assertEquals('2026年07月31日', context.paymentDueDateLabel);
      System.assertEquals(10000, context.amountExcludingTax);
      System.assertEquals(1000, context.taxAmount);
      System.assertEquals(11000, context.amountIncludingTax);
      System.assertEquals(1, context.lines.size());
      System.assertEquals('スナップショット商品', context.lines[0].ProductName__c);
      System.assertEquals('2026年6月分', context.lines[0].PeriodLabel__c);
      System.assertEquals('帳票発行株式会社', context.documentSetting.CompanyName__c);
      System.assertEquals('T1234567890123', context.documentSetting.InvoiceRegistrationNumber__c);
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
      System.assert(
        InvoiceDocumentService.STATUS_REQUIRED_MESSAGE.contains('請求取引状態'),
        'Core 第0.1節・第7.11節: 拒否は請求取引状態を指す'
      );
      System.assert(
        InvoiceDocumentService.STATUS_REQUIRED_MESSAGE.contains('確定済み'),
        'Core 第7.10節: 確定済み請求だけ発行できる'
      );
      System.assertEquals(
        false,
        InvoiceDocumentService.STATUS_REQUIRED_MESSAGE.contains('回収ステータス'),
        'Core 第7.11節: 回収・返金状態では発行可否を決めない'
      );
      System.assertEquals(
        false,
        InvoiceDocumentService.STATUS_REQUIRED_MESSAGE.contains('Confirmed'),
        'Core 第0.1節: 人が見る拒否文に Confirmed と出さない'
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
    Invoice__c invoice = new Invoice__c(Name = 'INV-1');

    String fileName = InvoiceDocumentService.buildFileName(invoice, null);

    System.assertEquals(
      true,
      fileName.contains(compact),
      '日付仕様 第8章: 請求日未設定のファイル名の今日は組織タイムゾーン'
    );
  }

  @IsTest
  static void issueInvoiceDocument_usesCmdtAndLinksTestPdf() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('Confirmed');

      Test.startTest();
      InvoiceDocumentService.IssueResult result =
        InvoiceDocumentService.issueInvoiceDocument(
          fixture.invoice.Id,
          'StandardInvoice'
        );
      Test.stopTest();

      System.assertNotEquals(null, result.contentVersionId);
      System.assertEquals('StandardInvoice', result.templateKey);
      System.assertEquals('InvoiceDocumentPdf', result.visualforcePage);
      System.assertEquals(
        'StandardInvoice_帳票取引先_20260630.pdf',
        result.fileName
      );
      ContentVersion saved = [
        SELECT Title, PathOnClient, VersionData, ContractDocumentIssued__c
        FROM ContentVersion
        WHERE Id = :result.contentVersionId
      ];
      System.assertEquals(
        true,
        saved.ContractDocumentIssued__c,
        'Core 第4.8節: 発行 insert に印を付ける'
      );
      System.assertEquals(
        'StandardInvoice_帳票取引先_20260630.pdf',
        saved.PathOnClient
      );
      System.assert(saved.VersionData.size() > 0, 'テスト用PDF Blobを保存すること');
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM ContentDocumentLink
          WHERE LinkedEntityId = :fixture.invoice.Id
        ]
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

      InvoiceDocumentPdfController controller =
        new InvoiceDocumentPdfController();

      System.assertEquals(true, controller.hasContext);
      System.assertEquals(fixture.invoice.Id, controller.context.invoice.Id);
      System.assertEquals(1, controller.context.lines.size());
    }
  }

  @IsTest
  static void pdfController_handlesMissingInvalidAndDraftIds() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Test.setCurrentPage(Page.InvoiceDocumentPdf);
      InvoiceDocumentPdfController missingController =
        new InvoiceDocumentPdfController();
      System.assertEquals(false, missingController.hasContext);

      ApexPages.currentPage().getParameters().put('id', 'invalid');
      InvoiceDocumentPdfController invalidController =
        new InvoiceDocumentPdfController();
      System.assertEquals(false, invalidController.hasContext);

      Fixture draftFixture = createFixture('Draft');
      ApexPages.currentPage().getParameters().put(
        'id',
        String.valueOf(draftFixture.invoice.Id)
      );
      InvoiceDocumentPdfController draftController =
        new InvoiceDocumentPdfController();
      System.assertEquals(false, draftController.hasContext);
      System.assert(!ApexPages.getMessages().isEmpty());
    }
  }

  @IsTest
  static void generatePdfBlob_returnsDummyDuringTest() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('Confirmed');
      Blob body = InvoiceDocumentService.generatePdfBlob(
        fixture.invoice.Id,
        'StandardInvoice'
      );
      System.assertNotEquals(null, body);
      System.assert(body.size() > 0);
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
      PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE);
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
      historystatus__c = 'Ordered',
      Version__c = 1,
      CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
      CurrentTermEndDate__c = Date.newInstance(2026, 6, 30)
    );
    ContractTestDataFactory.applyRequiredFields(history);
    insert history;

    Invoice__c invoice = new Invoice__c(
      ContractService__c = service.Id,
      ContractHistory__c = history.Id,
      InvoiceDate__c = Date.newInstance(2026, 6, 30),
      PaymentScheduledDate__c = Date.newInstance(2026, 7, 31),
      InvoiceTransactionStatus__c = collectionStatus == 'Draft'
        ? InvoiceTransactionStatusService.TX_DRAFT
        : InvoiceTransactionStatusService.TX_CONFIRMED,
      BillingAccountSnapShot__c = billingAccount.Id,
      BillingAddresseeSnapShot__c = '帳票取引先 請求担当',
      PaymentTermMethodSnapShot__c = BillingScheduleService.METHOD_MONTH_OFFSET,
      Amount__c = 10000,
      TaxAmount__c = 1000
    );
    ContractTestDataFactory.applyRequiredFields(invoice);
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
