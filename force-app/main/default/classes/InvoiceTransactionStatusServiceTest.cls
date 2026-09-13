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
      null
    );
    System.assertEquals(
      InvoiceTransactionStatusService.TX_CONFIRMED,
      invoice.InvoiceTransactionStatus__c,
      'Core 第7.11節: 未確定から確定済みへ遷移する'
    );
    System.assertEquals(
      InvoiceTransactionStatusService.organizationToday(),
      invoice.SystemIntegrationDate__c,
      'Core 第7.9節・第7.11節: 確定日は組織タイムゾーンの操作日'
    );
    System.assertEquals(
      InvoiceTransactionStatusService.COLLECTION_COMPLETED,
      invoice.CollectionRefundStatus__c,
      'Core 第7.11節: 税込0円請求は請求入出金0件でも確定時に完了'
    );
    System.assertEquals(
      InvoiceTransactionStatusService.organizationToday(),
      invoice.PaymentClearingCompletedDate__c,
      'Core 第7.11節・日付仕様 第8章: 完了日は状態更新と同じ処理で組織の操作日を書く'
    );
  }

  @IsTest
  static void rejectConfirmWhenNotDraft() {
    for (String status : new List<String>{
      InvoiceTransactionStatusService.TX_CONFIRMED,
      InvoiceTransactionStatusService.TX_CANCELLED
    }) {
      Invoice__c invoice = new Invoice__c(
        InvoiceTransactionStatus__c = status
      );
      Boolean thrown = false;
      try {
        InvoiceTransactionStatusService.applyConfirmed(
          new List<Invoice__c>{ invoice },
          null
        );
      } catch (InvoiceTransactionStatusService.InvoiceStatusException ex) {
        thrown = true;
        System.assertEquals(
          InvoiceTransactionStatusService.INVALID_CONFIRM_MESSAGE,
          ex.getMessage(),
          'Core 第7.11節: 未確定以外から確定済みへ遷移できない'
        );
      }
      System.assertEquals(true, thrown, 'Core 第7.11節: 不正な確定遷移を拒否する');
      System.assertEquals(
        status,
        invoice.InvoiceTransactionStatus__c,
        'Core 第7.11節: 拒否した請求取引状態を変更しない'
      );
    }
  }

  @IsTest
  static void collectionNotStartedWhenNetDiffersAndNoInvoicePurpose() {
    Invoice__c invoice = invoiceWithTaxInclusive(
      6000,
      5000,
      Date.newInstance(2026, 7, 1)
    );
    InvoiceTransactionStatusService.applyCollectionRefund(invoice);
    System.assertEquals(
      InvoiceTransactionStatusService.COLLECTION_NOT_STARTED,
      invoice.CollectionRefundStatus__c,
      'Core 第7.11節: 請求金額目的の有効入出金が0件でNetと税込が不一致なら未対応'
    );
    System.assertEquals(
      null,
      invoice.PaymentClearingCompletedDate__c,
      'Core 第7.11節: 未対応への更新と同じ処理で完了日をクリアする'
    );
  }

  @IsTest
  static void collectionInProgressWhenNetDiffersAndInvoicePurposeExists() {
    Invoice__c invoice = invoiceWithTaxInclusive(
      6000,
      5000,
      Date.newInstance(2026, 7, 1)
    );
    InvoiceTransactionStatusService.applyCollectionRefund(invoice, 1);
    System.assertEquals(
      InvoiceTransactionStatusService.COLLECTION_IN_PROGRESS,
      invoice.CollectionRefundStatus__c,
      'Core 第7.11節: 請求金額目的の有効入出金が1件以上あり不一致なら対応中'
    );
    System.assertEquals(
      null,
      invoice.PaymentClearingCompletedDate__c,
      'Core 第7.11節: 対応中への更新と同じ処理で完了日をクリアする'
    );
  }

  @IsTest
  static void applyCancelled_confirmedBecomesCancelled() {
    Invoice__c invoice = new Invoice__c(
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED,
      DeliveryStatus__c = InvoiceTransactionStatusService.DELIVERY_SENT,
      SentDate__c = Date.newInstance(2026, 7, 1),
      CollectionRefundStatus__c = InvoiceTransactionStatusService.COLLECTION_COMPLETED,
      PaymentClearingCompletedDate__c = Date.newInstance(2026, 7, 2)
    );
    InvoiceTransactionStatusService.applyCancelled(
      new List<Invoice__c>{ invoice }
    );
    System.assertEquals(
      InvoiceTransactionStatusService.TX_CANCELLED,
      invoice.InvoiceTransactionStatus__c,
      'Core 第7.11節: 確定済みから取消済みだけを許す'
    );
    System.assertEquals(
      InvoiceTransactionStatusService.DELIVERY_SENT,
      invoice.DeliveryStatus__c,
      'Core 第7.11節: 取消前の送付状態を監査用に保持する'
    );
    System.assertEquals(
      Date.newInstance(2026, 7, 1),
      invoice.SentDate__c,
      'Core 第7.11節: 取消時に送付日を変更しない'
    );
    System.assertEquals(
      InvoiceTransactionStatusService.COLLECTION_COMPLETED,
      invoice.CollectionRefundStatus__c,
      'Core 第7.11節: 取消済みは回収・返金判定の対象外とし、取消前の値を保持する'
    );
    System.assertEquals(
      Date.newInstance(2026, 7, 2),
      invoice.PaymentClearingCompletedDate__c,
      'Core 第7.11節: 取消時に完了日を変更しない'
    );
  }

  @IsTest
  static void applyCancelled_nonConfirmedThrowsKnownMessage() {
    for (String status : new List<String>{
      InvoiceTransactionStatusService.TX_DRAFT,
      InvoiceTransactionStatusService.TX_CANCELLED
    }) {
      Invoice__c invoice = new Invoice__c(
        InvoiceTransactionStatus__c = status
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
          ex.getMessage(),
          'Core 第7.9.3節・第7.11節: 確定済み以外は取消できない'
        );
      }
      System.assertEquals(true, thrown, 'Core 第7.11節: 不正な取消遷移を拒否する');
      System.assertEquals(
        status,
        invoice.InvoiceTransactionStatus__c,
        'Core 第7.11節: 拒否した請求取引状態を変更しない'
      );
    }
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
    System.assertEquals(
      true,
      next.hasErrors(),
      'Core 第7.11節: 請求取引状態の直接更新を拒否する'
    );
    System.assertEquals(
      InvoiceTransactionStatusService.DIRECT_EDIT_MESSAGE,
      next.getErrors()[0].getMessage(),
      'Core 第7.11節: 直接編集拒否の理由を返す'
    );
  }

  @IsTest
  static void rejectDirectStatusEdits_blocksCollectionChange() {
    Id fakeId =
      Invoice__c.SObjectType.getDescribe().getKeyPrefix() + '000000000007AAA';
    Invoice__c prior = new Invoice__c(
      Id = fakeId,
      CollectionRefundStatus__c = InvoiceTransactionStatusService.COLLECTION_NOT_STARTED
    );
    Invoice__c next = new Invoice__c(
      Id = fakeId,
      CollectionRefundStatus__c = InvoiceTransactionStatusService.COLLECTION_IN_PROGRESS
    );
    InvoiceTransactionStatusService.allowStatusWrite = false;
    InvoiceTransactionStatusService.rejectDirectStatusEdits(
      new List<Invoice__c>{ next },
      new Map<Id, Invoice__c>{ fakeId => prior }
    );
    System.assertEquals(
      true,
      next.hasErrors(),
      'Core 第7.11節: 回収・返金状態の直接更新を拒否する'
    );
    System.assertEquals(
      InvoiceTransactionStatusService.DIRECT_EDIT_MESSAGE,
      next.getErrors()[0].getMessage()
    );
  }

  @IsTest
  static void rejectDirectStatusEdits_blocksNonSeedStatusOnInsert() {
    Invoice__c confirmed = new Invoice__c(
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED
    );
    Invoice__c collecting = new Invoice__c(
      CollectionRefundStatus__c = InvoiceTransactionStatusService.COLLECTION_IN_PROGRESS
    );
    InvoiceTransactionStatusService.allowStatusWrite = false;
    InvoiceTransactionStatusService.rejectDirectStatusEdits(
      new List<Invoice__c>{ confirmed, collecting },
      null
    );
    for (Invoice__c invoice : new List<Invoice__c>{ confirmed, collecting }) {
      System.assertEquals(
        true,
        invoice.hasErrors(),
        'Core 第7.11節: Insertでも種以外の状態の直接指定を拒否する'
      );
      System.assertEquals(
        InvoiceTransactionStatusService.DIRECT_EDIT_MESSAGE,
        invoice.getErrors()[0].getMessage()
      );
    }
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
    System.assertEquals(
      InvoiceTransactionStatusService.COLLECTION_NOT_STARTED,
      blank.CollectionRefundStatus__c,
      'Core 第7.11節: 回収・返金状態の種は未対応'
    );
    System.assertEquals(false, seeded.hasErrors());
    System.assertEquals(
      InvoiceTransactionStatusService.TX_DRAFT,
      seeded.InvoiceTransactionStatus__c
    );
    System.assertEquals(
      InvoiceTransactionStatusService.COLLECTION_NOT_STARTED,
      seeded.CollectionRefundStatus__c,
      'Core 第7.11節: 未指定の回収・返金状態を未対応で初期化する'
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
        null
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
        null
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
        null
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
    InvoiceTransactionStatusService.applyConfirmed(null, null);
    InvoiceTransactionStatusService.applyConfirmed(
      new List<Invoice__c>(),
      null
    );
    InvoiceTransactionStatusService.applyConfirmed(
      new List<Invoice__c>{ null },
      null
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
      InvoiceTransactionStatusService.DELIVERY_UNSENT,
      invoice.DeliveryStatus__c,
      'Core 第7.11節: 送付状態と送付日を同じ専用処理で更新する'
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
    Invoice__c invoice = invoiceWithTaxInclusive(1100, 1100, kept);
    InvoiceTransactionStatusService.applyCollectionRefund(invoice, 0);
    System.assertEquals(
      InvoiceTransactionStatusService.COLLECTION_COMPLETED,
      invoice.CollectionRefundStatus__c,
      'Core 第7.11節: 請求金額Netと請求税込額が一致すれば完了'
    );
    System.assertEquals(
      kept,
      invoice.PaymentClearingCompletedDate__c,
      'Core 第7.11節: 完了日は既にあれば上書きしない'
    );
    System.assertEquals(
      1100,
      InvoiceTransactionStatusService.resolveTaxInclusive(invoice),
      'Core 第7.11節: 請求税込の正本はTaxInclusiveAmount__c'
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

  private static Invoice__c invoiceWithTaxInclusive(
    Decimal taxInclusive,
    Decimal invoiceNet,
    Date completedDate
  ) {
    return (Invoice__c) JSON.deserialize(
      JSON.serialize(
        new Map<String, Object>{
          'attributes' => new Map<String, Object>{ 'type' => 'Invoice__c' },
          'InvoiceTransactionStatus__c' => InvoiceTransactionStatusService.TX_CONFIRMED,
          'TaxInclusiveAmount__c' => taxInclusive,
          'InvoicePaymentNet__c' => invoiceNet,
          'PaymentClearingCompletedDate__c' => completedDate
        }
      ),
      Invoice__c.class
    );
  }
}
