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
      System.assertEquals(
        InvoiceTransactionStatusService.INVALID_CONFIRM_MESSAGE,
        ex.getMessage(),
        'Core 第7.11節: 未確定の請求だけ確定できる'
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void collectionNotStartedWhenNetDiffersAndNoInvoicePurpose() {
    Invoice__c invoice = new Invoice__c(
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED,
      InvoicePaymentNet__c = 5000
    );
    InvoiceTransactionStatusService.applyCollectionRefund(invoice);
    System.assertEquals(
      InvoiceTransactionStatusService.COLLECTION_NOT_STARTED,
      invoice.CollectionRefundStatus__c,
      'Core 第7.11節: 請求金額目的の有効入出金が0件でNetと税込が不一致なら未対応'
    );
  }

  @IsTest
  static void collectionInProgressWhenNetDiffersAndInvoicePurposeExists() {
    Invoice__c invoice = new Invoice__c(
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED,
      InvoicePaymentNet__c = 5000
    );
    InvoiceTransactionStatusService.applyCollectionRefund(invoice, 1);
    System.assertEquals(
      InvoiceTransactionStatusService.COLLECTION_IN_PROGRESS,
      invoice.CollectionRefundStatus__c,
      'Core 第7.11節: 請求金額目的の有効入出金が1件以上あり不一致なら対応中'
    );
  }

  @IsTest
  static void applyCancelled_confirmedBecomesCancelled() {
    Invoice__c invoice = new Invoice__c(
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED
    );
    InvoiceTransactionStatusService.applyCancelled(
      new List<Invoice__c>{ invoice }
    );
    System.assertEquals(
      InvoiceTransactionStatusService.TX_CANCELLED,
      invoice.InvoiceTransactionStatus__c,
      'Core 第7.11節: 確定済みから取消済みだけを許す'
    );
  }

  @IsTest
  static void applyCancelled_draftThrowsKnownMessage() {
    Invoice__c invoice = new Invoice__c(
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_DRAFT
    );
    Boolean thrown = false;
    try {
      InvoiceTransactionStatusService.applyCancelled(
        new List<Invoice__c>{ invoice }
      );
    } catch (InvoiceTransactionStatusService.InvoiceStatusException ex) {
      thrown = true;
      System.assertEquals(
        InvoiceTransactionStatusService.INVALID_CANCEL_MESSAGE,
        ex.getMessage()
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void applyDelivery_cancelledThrowsKnownMessage() {
    Invoice__c invoice = new Invoice__c(
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CANCELLED
    );
    Boolean thrown = false;
    try {
      InvoiceTransactionStatusService.applyDelivery(
        invoice,
        InvoiceTransactionStatusService.DELIVERY_SENT,
        Date.newInstance(2026, 8, 1)
      );
    } catch (InvoiceTransactionStatusService.InvoiceStatusException ex) {
      thrown = true;
      System.assertEquals(
        '取消済みの請求は送付状態を変えられません。',
        ex.getMessage()
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void applyCollectionRefund_draftIsNotStarted() {
    Invoice__c invoice = new Invoice__c(
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_DRAFT,
      InvoicePaymentNet__c = 5000
    );
    InvoiceTransactionStatusService.applyCollectionRefund(invoice);
    System.assertEquals(
      InvoiceTransactionStatusService.COLLECTION_NOT_STARTED,
      invoice.CollectionRefundStatus__c,
      'Core 第7.11節: 未確定は回収・返金未対応'
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
  static void rejectDirectStatusEdits_insertUnsentDefault_seedsNotApplicableWhenPdfOnly() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractTestDataFactory.initTestContext();
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.InvoiceSendMode__c = ContractDocumentSettingService.MODE_PDF_ONLY;
      update setting;
      ContractDocumentSettingService.clearCache();

      Invoice__c invoice = new Invoice__c(
        DeliveryStatus__c = InvoiceTransactionStatusService.DELIVERY_UNSENT
      );
      InvoiceTransactionStatusService.allowStatusWrite = false;
      InvoiceTransactionStatusService.rejectDirectStatusEdits(
        new List<Invoice__c>{ invoice },
        null
      );
      System.assertEquals(false, invoice.hasErrors());
      System.assertEquals(
        InvoiceTransactionStatusService.DELIVERY_NOT_APPLICABLE,
        invoice.DeliveryStatus__c,
        '第7.11節: 項目初期値 Unsent は PDFのみの種 NotApplicable へ上書きする'
      );
    }
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

  @IsTest
  static void applyConfirmedAndCancelled_emptyOrNullDoNotThrow() {
    InvoiceTransactionStatusService.applyConfirmed(null, Date.newInstance(2026, 8, 1));
    InvoiceTransactionStatusService.applyConfirmed(
      new List<Invoice__c>(),
      Date.newInstance(2026, 8, 1)
    );
    InvoiceTransactionStatusService.applyConfirmed(
      new List<Invoice__c>{ null },
      Date.newInstance(2026, 8, 1)
    );
    InvoiceTransactionStatusService.applyCancelled(null);
    InvoiceTransactionStatusService.applyCancelled(new List<Invoice__c>());
    InvoiceTransactionStatusService.applyCancelled(new List<Invoice__c>{ null });
    InvoiceTransactionStatusService.applyDelivery(null, InvoiceTransactionStatusService.DELIVERY_SENT, Date.today());
    InvoiceTransactionStatusService.applyCollectionRefund(null);
    InvoiceTransactionStatusService.seedDefaults(null);
    System.assertEquals(
      false,
      InvoiceTransactionStatusService.isConfirmed(null),
      'Core 第7.11節: 空の請求は確定済みではない'
    );
    System.assertEquals(false, InvoiceTransactionStatusService.isCancelled(null));
    System.assertEquals(false, InvoiceTransactionStatusService.isDraft(null));
    System.assertEquals(
      0,
      InvoiceTransactionStatusService.resolveTaxInclusive(null),
      'Core 第7.11節: 空の請求の税込は0'
    );
  }

  @IsTest
  static void applyDelivery_setsAndClearsSentDate() {
    Invoice__c invoice = new Invoice__c(
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED
    );
    InvoiceTransactionStatusService.applyDelivery(
      invoice,
      InvoiceTransactionStatusService.DELIVERY_SENT,
      Date.newInstance(2026, 8, 2)
    );
    System.assertEquals(
      InvoiceTransactionStatusService.DELIVERY_SENT,
      invoice.DeliveryStatus__c,
      'Core 第7.10節・第7.11節: 送付成功は送付状態を送付済にする'
    );
    System.assertEquals(
      Date.newInstance(2026, 8, 2),
      invoice.SentDate__c,
      'Core 第7.11節: 送付日は送付と同じ処理で書く'
    );
    InvoiceTransactionStatusService.applyDelivery(
      invoice,
      InvoiceTransactionStatusService.DELIVERY_UNSENT,
      Date.newInstance(2026, 8, 3)
    );
    System.assertEquals(
      null,
      invoice.SentDate__c,
      'Core 第7.11節: 送付済以外は送付日をクリアする'
    );
  }

  @IsTest
  static void applyCollectionRefund_cancelledStaysUntouched() {
    Invoice__c invoice = new Invoice__c(
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CANCELLED,
      CollectionRefundStatus__c = InvoiceTransactionStatusService.COLLECTION_IN_PROGRESS,
      PaymentClearingCompletedDate__c = Date.newInstance(2026, 7, 1)
    );
    InvoiceTransactionStatusService.applyCollectionRefund(invoice, 2);
    System.assertEquals(
      InvoiceTransactionStatusService.COLLECTION_IN_PROGRESS,
      invoice.CollectionRefundStatus__c,
      'Core 第7.11節: 取消済みは回収・返金判定の対象外。取消前の値を保つ'
    );
    System.assertEquals(Date.newInstance(2026, 7, 1), invoice.PaymentClearingCompletedDate__c);
  }

  @IsTest
  static void applyCollectionRefund_matchingNetIsCompletedAndKeepsClearingDate() {
    Date kept = Date.newInstance(2026, 6, 10);
    Invoice__c invoice = new Invoice__c(
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED,
      InvoicePaymentNet__c = 0,
      PaymentClearingCompletedDate__c = kept
    );
    InvoiceTransactionStatusService.applyCollectionRefund(invoice, 0);
    System.assertEquals(
      InvoiceTransactionStatusService.COLLECTION_COMPLETED,
      invoice.CollectionRefundStatus__c,
      'Core 第7.11節: 税込0円請求は入出金0件でも完了。Netと税込が一致すれば完了'
    );
    System.assertEquals(
      kept,
      invoice.PaymentClearingCompletedDate__c,
      'Core 第7.11節: 完了日は既にあれば上書きしない'
    );
    Invoice__c fromAmount = new Invoice__c(
      Amount__c = 1000,
      TaxAmount__c = 100
    );
    System.assertEquals(
      1100,
      InvoiceTransactionStatusService.resolveTaxInclusive(fromAmount),
      'Core 第7.11節: 税込正本が空なら税抜と税額の合計'
    );
  }

  @IsTest
  static void rejectDirectStatusEdits_allowWriteAndBlockDeliveryChange() {
    InvoiceTransactionStatusService.allowStatusWrite = true;
    Invoice__c allowed = new Invoice__c(
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED
    );
    InvoiceTransactionStatusService.rejectDirectStatusEdits(
      new List<Invoice__c>{ allowed },
      null
    );
    System.assertEquals(
      false,
      allowed.hasErrors(),
      'Core 第7.11節: 専用処理の書込だけ状態更新を許す'
    );
    InvoiceTransactionStatusService.allowStatusWrite = false;
    Id fakeId =
      Invoice__c.SObjectType.getDescribe().getKeyPrefix() + '000000000008AAA';
    Invoice__c prior = new Invoice__c(
      Id = fakeId,
      DeliveryStatus__c = InvoiceTransactionStatusService.DELIVERY_UNSENT
    );
    Invoice__c next = new Invoice__c(
      Id = fakeId,
      DeliveryStatus__c = InvoiceTransactionStatusService.DELIVERY_SENT
    );
    InvoiceTransactionStatusService.rejectDirectStatusEdits(
      new List<Invoice__c>{ next },
      new Map<Id, Invoice__c>{ fakeId => prior }
    );
    System.assertEquals(true, next.hasErrors());
    System.assertEquals(
      InvoiceTransactionStatusService.DIRECT_EDIT_MESSAGE,
      next.getErrors()[0].getMessage(),
      'Core 第7.11節: 送付状態の直接編集も拒否する'
    );
  }
}
