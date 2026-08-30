@IsTest
private class InvoiceTransactionStatusServiceTest {
  @IsTest
  static void confirmDraftAndCompleteZeroInvoice() {
    Invoice__c invoice = new Invoice__c(
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_DRAFT,
      InvoicePaymentNet__c = 0
    );
    InvoiceTransactionStatusService.applyConfirmed(
      new List<Invoice__c>{ invoice },
      Date.newInstance(2026, 8, 1)
    );
    System.assertEquals(
      InvoiceTransactionStatusService.TX_CONFIRMED,
      invoice.InvoiceTransactionStatus__c
    );
    System.assertEquals(
      Date.newInstance(2026, 8, 1),
      invoice.SystemIntegrationDate__c
    );
      System.assertEquals(
        InvoiceTransactionStatusService.COLLECTION_COMPLETED,
        invoice.CollectionRefundStatus__c
      );
      System.assertEquals(
        InvoiceTransactionStatusService.organizationToday(),
        invoice.PaymentClearingCompletedDate__c,
        '日付仕様 第8章: 回収完了日は組織タイムゾーンの当日'
      );
  }

  @IsTest
  static void applyConfirmed_nullDate_usesOrganizationToday() {
    Invoice__c invoice = new Invoice__c(
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_DRAFT,
      InvoicePaymentNet__c = 0
    );
    InvoiceTransactionStatusService.applyConfirmed(
      new List<Invoice__c>{ invoice },
      null
    );
    System.assertEquals(
      InvoiceTransactionStatusService.organizationToday(),
      invoice.SystemIntegrationDate__c,
      'Core 第7.9節・日付仕様 第8章: nullなら組織タイムゾーンの操作日。Date.today()で埋めない'
    );
  }

  @IsTest
  static void rejectConfirmWhenAlreadyConfirmed() {
    Invoice__c invoice = new Invoice__c(
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED
    );
    Boolean thrown = false;
    try {
      InvoiceTransactionStatusService.applyConfirmed(
        new List<Invoice__c>{ invoice },
        Date.today()
      );
    } catch (InvoiceTransactionStatusService.InvoiceStatusException ex) {
      thrown = true;
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void collectionInProgressWhenNetDiffers() {
    Invoice__c invoice = new Invoice__c(
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED,
      InvoicePaymentNet__c = 5000
    );
    InvoiceTransactionStatusService.applyCollectionRefund(invoice);
    System.assertEquals(
      InvoiceTransactionStatusService.COLLECTION_IN_PROGRESS,
      invoice.CollectionRefundStatus__c
    );
  }

  @IsTest
  static void rejectDirectStatusEdits_blocksTransactionChange() {
    Id fakeId =
      Invoice__c.SObjectType.getDescribe().getKeyPrefix() + '000000000009AAA';
    Invoice__c prior = new Invoice__c(
      Id = fakeId,
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_DRAFT
    );
    Invoice__c next = new Invoice__c(
      Id = fakeId,
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED
    );
    InvoiceTransactionStatusService.allowStatusWrite = false;
    InvoiceTransactionStatusService.rejectDirectStatusEdits(
      new List<Invoice__c>{ next },
      new Map<Id, Invoice__c>{ fakeId => prior }
    );
    System.assertEquals(true, next.hasErrors());
  }

  @IsTest
  static void rejectDirectStatusEdits_blocksConfirmedOnInsert() {
    Invoice__c invoice = new Invoice__c(
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED
    );
    InvoiceTransactionStatusService.allowStatusWrite = false;
    InvoiceTransactionStatusService.rejectDirectStatusEdits(
      new List<Invoice__c>{ invoice },
      null
    );
    System.assertEquals(true, invoice.hasErrors());
    System.assertEquals(
      InvoiceTransactionStatusService.DIRECT_EDIT_MESSAGE,
      invoice.getErrors()[0].getMessage()
    );
  }

  @IsTest
  static void rejectDirectStatusEdits_allowsBlankAndSeedOnInsert() {
    Invoice__c blank = new Invoice__c();
    Invoice__c seeded = new Invoice__c(
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_DRAFT
    );
    InvoiceTransactionStatusService.allowStatusWrite = false;
    InvoiceTransactionStatusService.rejectDirectStatusEdits(
      new List<Invoice__c>{ blank, seeded },
      null
    );
    System.assertEquals(false, blank.hasErrors());
    System.assertEquals(
      InvoiceTransactionStatusService.TX_DRAFT,
      blank.InvoiceTransactionStatus__c
    );
    System.assertEquals(false, seeded.hasErrors());
    System.assertEquals(
      InvoiceTransactionStatusService.TX_DRAFT,
      seeded.InvoiceTransactionStatus__c
    );
  }

  @IsTest
  static void seedDefaults_pdfOnlyAndUnusedAreNotApplicable() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractTestDataFactory.initTestContext();
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.InvoiceSendMode__c = ContractDocumentSettingService.MODE_PDF_ONLY;
      update setting;
      ContractDocumentSettingService.clearCache();

      Invoice__c pdfOnly = new Invoice__c();
      InvoiceTransactionStatusService.seedDefaults(pdfOnly);
      System.assertEquals(
        InvoiceTransactionStatusService.DELIVERY_NOT_APPLICABLE,
        pdfOnly.DeliveryStatus__c,
        '第7.11節: PDFのみの送付状態初期値は NotApplicable'
      );

      setting.InvoiceSendMode__c = ContractDocumentSettingService.MODE_UNUSED;
      update setting;
      ContractDocumentSettingService.clearCache();
      Invoice__c unused = new Invoice__c();
      InvoiceTransactionStatusService.seedDefaults(unused);
      System.assertEquals(
        InvoiceTransactionStatusService.DELIVERY_NOT_APPLICABLE,
        unused.DeliveryStatus__c,
        '第7.11節: 使わないの送付状態初期値は NotApplicable'
      );

      setting.InvoiceSendMode__c = ContractDocumentSettingService.MODE_PDF_AND_EMAIL;
      update setting;
      ContractDocumentSettingService.clearCache();
      Invoice__c mailed = new Invoice__c();
      InvoiceTransactionStatusService.seedDefaults(mailed);
      System.assertEquals(
        InvoiceTransactionStatusService.DELIVERY_UNSENT,
        mailed.DeliveryStatus__c,
        '第7.11節: PDFとメール送付の送付状態初期値は Unsent'
      );

      Invoice__c emailInvoice = new Invoice__c(
        InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_DRAFT,
        InvoicePaymentNet__c = 0,
        InvoiceDeliveryMethodSnapShot__c = InvoiceDeliveryMethodService.EMAIL
      );
      InvoiceTransactionStatusService.applyConfirmed(
        new List<Invoice__c>{ emailInvoice },
        Date.newInstance(2026, 8, 1)
      );
      System.assertEquals(
        InvoiceTransactionStatusService.DELIVERY_UNSENT,
        emailInvoice.DeliveryStatus__c,
        '第7.11節: 確定時メールは Unsent'
      );

      Invoice__c postInvoice = new Invoice__c(
        InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_DRAFT,
        InvoicePaymentNet__c = 0,
        InvoiceDeliveryMethodSnapShot__c = InvoiceDeliveryMethodService.POST
      );
      InvoiceTransactionStatusService.applyConfirmed(
        new List<Invoice__c>{ postInvoice },
        Date.newInstance(2026, 8, 1)
      );
      System.assertEquals(
        InvoiceTransactionStatusService.DELIVERY_NOT_APPLICABLE,
        postInvoice.DeliveryStatus__c,
        '第7.11節: 確定時郵送は NotApplicable'
      );

      Invoice__c noneInvoice = new Invoice__c(
        InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_DRAFT,
        InvoicePaymentNet__c = 0,
        InvoiceDeliveryMethodSnapShot__c = InvoiceDeliveryMethodService.NONE
      );
      InvoiceTransactionStatusService.applyConfirmed(
        new List<Invoice__c>{ noneInvoice },
        Date.newInstance(2026, 8, 1)
      );
      System.assertEquals(
        InvoiceTransactionStatusService.DELIVERY_NOT_APPLICABLE,
        noneInvoice.DeliveryStatus__c,
        '第7.11節: 確定時送付なしは NotApplicable'
      );
    }
  }

  @IsTest
  static void systemIntegrationDate_helpIsConfirmDayNotCollectionStatus() {
    String helpText = Invoice__c.SystemIntegrationDate__c.getDescribe()
      .getInlineHelpText();
    System.assertNotEquals(null, helpText);
    System.assert(
      helpText.contains('請求取引状態'),
      'Core 第7.9節・第7.11節: 確定日ヘルプは請求取引状態を指す'
    );
    System.assert(
      helpText.contains('確定済み'),
      'Core 第7.9節・第7.11節: 確定日は請求取引状態を確定済みにした日'
    );
    System.assert(
      !helpText.contains('回収ステータス'),
      'Core 第7.11節: 確定日ヘルプに回収ステータスと出さない'
    );
  }

  @IsTest
  static void dueStatus_labelIsDueStateNotDueSituation() {
    System.assertEquals(
      '期限状態',
      Invoice__c.DueStatus__c.getDescribe().getLabel(),
      'Core 第7.11節: 期限状態の表示名は期限状態。期限状況ではない'
    );
  }
}
