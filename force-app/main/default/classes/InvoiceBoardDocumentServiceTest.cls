@IsTest
private class InvoiceBoardDocumentServiceTest {
  @TestSetup
  static void setup() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void previewIssueFromPreview_returnsPatternFileNameWithoutSaving() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.InvoiceSendMode__c = 'PdfOnly';
      setting.InvoiceDefaultDocumentTemplateKey__c = 'StandardInvoice';
      update setting;
      ContractDocumentSettingService.clearCache();

      Invoice__c invoice = createConfirmedInvoice();
      Integer filesBefore = [
        SELECT COUNT()
        FROM ContentDocumentLink
        WHERE LinkedEntityId = :invoice.Id
      ];

      Test.startTest();
      InvoiceBoardDocumentService.DocumentResultDto preview = InvoiceBoardDocumentService.previewIssueFromPreview(
        invoice.Id,
        'StandardInvoice'
      );
      Test.stopTest();

      System.assertNotEquals(null, preview.fileName);
      System.assert(
        preview.fileName.endsWith('.pdf'),
        'Core 第11.3.2節: 発行ファイル名はパターンの参照'
      );
      System.assertEquals('StandardInvoice', preview.documentTemplateKey);
      Integer filesAfter = [
        SELECT COUNT()
        FROM ContentDocumentLink
        WHERE LinkedEntityId = :invoice.Id
      ];
      System.assertEquals(
        filesBefore,
        filesAfter,
        'Core 第4.8節: ファイル名を見せるだけで発行しない'
      );
    }
  }

  @IsTest
  static void issueFromPreview_rejectsUnusedMode() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.InvoiceSendMode__c = 'Unused';
      update setting;
      ContractDocumentSettingService.clearCache();

      Invoice__c invoice = createConfirmedInvoice();
      Boolean thrown = false;
      try {
        InvoiceBoardDocumentService.issueFromPreview(
          invoice.Id,
          'StandardInvoice',
          token(invoice.Id)
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          InvoiceBoardDocumentService.UNUSED_BLOCK_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void sendFromPreview_rejectsPdfOnly() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.InvoiceSendMode__c = 'PdfOnly';
      update setting;
      ContractDocumentSettingService.clearCache();

      Invoice__c invoice = createConfirmedInvoice();
      Boolean thrown = false;
      try {
        InvoiceBoardDocumentService.sendFromPreview(
          invoice.Id,
          'StandardInvoice',
          null,
          token(invoice.Id)
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          InvoiceBoardDocumentService.SEND_MODE_BLOCK_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void sendFromPreview_rejectsWhenSnapshotIsNotEmail() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.InvoiceSendMode__c = 'PdfAndEmail';
      update setting;
      ContractDocumentSettingService.clearCache();

      Invoice__c invoice = createConfirmedInvoice(
        InvoiceDeliveryMethodService.POST
      );
      Boolean thrown = false;
      try {
        InvoiceBoardDocumentService.sendFromPreview(
          invoice.Id,
          'StandardInvoice',
          null,
          token(invoice.Id)
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          InvoiceDeliveryMethodService.SEND_NOT_ALLOWED_MESSAGE,
          ex.getMessage(),
          'Core 第7.10節: 届け方が郵送なら送付を拒否する'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void sendFromPreview_withoutCatalog_throws() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.InvoiceSendMode__c = 'PdfAndEmail';
      setting.InvoiceOrgWideEmailAddress__c = 'noreply@example.com';
      update setting;
      ContractDocumentSettingService.clearCache();
      ContractEmailTemplateService.clearTestState();

      Invoice__c invoice = createConfirmedInvoice();
      Boolean thrown = false;
      try {
        InvoiceBoardDocumentService.sendFromPreview(
          invoice.Id,
          'StandardInvoice',
          null,
          token(invoice.Id)
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assert(
          ex.getMessage()
            .contains(ContractEmailTemplateService.MISSING_API_NAME_MESSAGE),
          'Core 第11.3.2節: カタログ無しでは送付しない。実際: ' +
            ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void sendFromPreview_writesHistoryWithoutDelegating() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.InvoiceSendMode__c = 'PdfAndEmail';
      setting.InvoiceDefaultEmailTemplateApiName__c = 'InvoiceMail';
      setting.InvoiceOrgWideEmailAddress__c = 'noreply@example.com';
      update setting;
      ContractDocumentSettingService.clearCache();
      ContractEmailTemplateService.seedActiveRowForTest(
        ContractEmailTemplateService.TYPE_INVOICE,
        'InvoiceMail'
      );

      Invoice__c invoice = createConfirmedInvoice();
      InvoiceBoardDocumentService.SendDraftDto draft = new InvoiceBoardDocumentService.SendDraftDto();
      draft.toAddresses = invoice.BillingEmailToSnapShot__c;
      draft.ccAddresses = '';
      draft.bccAddresses = '';
      draft.subject = '件名';
      draft.body = '本文';
      draft.fileName = 'invoice-send.pdf';
      draft.attachmentId = InvoiceBoardDocumentService.ATTACHMENT_NEW;
      InvoiceBoardDocumentService.skipEmailSend = true;
      InvoiceBoardDocumentService.DocumentResultDto result;
      try {
        result = InvoiceBoardDocumentService.sendFromPreview(
          invoice.Id,
          'StandardInvoice',
          null,
          token(invoice.Id),
          draft
        );
      } finally {
        InvoiceBoardDocumentService.skipEmailSend = false;
      }
      Invoice__c sent = [
        SELECT DeliveryStatus__c, SentDate__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(
        InvoiceTransactionStatusService.DELIVERY_SENT,
        sent.DeliveryStatus__c,
        'Core 第7.11節: 送付成功時に送付状態を送付済へ更新する'
      );
      System.assertEquals(
        InvoiceTransactionStatusService.organizationToday(),
        sent.SentDate__c,
        '日付仕様 第8章: 送付日は組織タイムゾーンの当日'
      );
    }
  }

  @IsTest
  static void sendFromPreview_blankToken_sends() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.InvoiceSendMode__c = 'PdfAndEmail';
      setting.InvoiceDefaultEmailTemplateApiName__c = 'InvoiceMail';
      setting.InvoiceOrgWideEmailAddress__c = 'noreply@example.com';
      update setting;
      ContractDocumentSettingService.clearCache();
      ContractEmailTemplateService.seedActiveRowForTest(
        ContractEmailTemplateService.TYPE_INVOICE,
        'InvoiceMail'
      );

      Invoice__c invoice = createConfirmedInvoice();
      InvoiceBoardDocumentService.SendDraftDto draft = new InvoiceBoardDocumentService.SendDraftDto();
      draft.toAddresses = invoice.BillingEmailToSnapShot__c;
      draft.ccAddresses = '';
      draft.bccAddresses = '';
      draft.subject = '件名';
      draft.body = '本文';
      draft.fileName = 'invoice-send.pdf';
      draft.attachmentId = InvoiceBoardDocumentService.ATTACHMENT_NEW;
      InvoiceBoardDocumentService.skipEmailSend = true;
      InvoiceBoardDocumentService.DocumentResultDto result;
      try {
        result = InvoiceBoardDocumentService.sendFromPreview(
          invoice.Id,
          'StandardInvoice',
          null,
          null,
          draft
        );
      } finally {
        InvoiceBoardDocumentService.skipEmailSend = false;
      }
      Invoice__c sent = [
        SELECT DeliveryStatus__c, SentDate__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(
        InvoiceTransactionStatusService.DELIVERY_SENT,
        sent.DeliveryStatus__c,
        'Core 第4.3.12節: 請求の個別送付は比較なし'
      );
      System.assertNotEquals(null, result);
    }
  }

  @IsTest
  static void issueFromPreview_blankToken_issues() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.InvoiceSendMode__c = 'PdfOnly';
      setting.InvoiceDefaultDocumentTemplateKey__c = 'StandardInvoice';
      update setting;
      ContractDocumentSettingService.clearCache();

      Invoice__c invoice = createConfirmedInvoice();
      InvoiceBoardDocumentService.DocumentResultDto issued = InvoiceBoardDocumentService.issueFromPreview(
        invoice.Id,
        'StandardInvoice',
        null
      );
      System.assertNotEquals(
        null,
        issued.fileName,
        'Core 第4.3.12節: 請求の個別PDF発行は比較なし'
      );
    }
  }

  @IsTest
  static void issueFromPreview_secondCallAfterFirst_succeeds() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.InvoiceSendMode__c = 'PdfOnly';
      setting.InvoiceDefaultDocumentTemplateKey__c = 'StandardInvoice';
      update setting;
      ContractDocumentSettingService.clearCache();

      Invoice__c invoice = createConfirmedInvoice();
      Test.startTest();
      InvoiceBoardDocumentService.DocumentResultDto first = InvoiceBoardDocumentService.issueFromPreview(
        invoice.Id,
        'StandardInvoice',
        null
      );
      InvoiceBoardDocumentService.DocumentResultDto second = InvoiceBoardDocumentService.issueFromPreview(
        invoice.Id,
        'StandardInvoice',
        null
      );
      Test.stopTest();
      System.assertNotEquals(null, first.fileName);
      System.assertNotEquals(
        null,
        second.fileName,
        'Core 第7.10節: 終わったあとの再発行は可'
      );
    }
  }

  @IsTest
  static void previewFromPreview_returnsSnapshotRecipientsAndFrom() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.InvoiceSendMode__c = 'PdfAndEmail';
      setting.InvoiceDefaultEmailTemplateApiName__c = 'InvoiceMail';
      setting.InvoiceOrgWideEmailAddress__c = 'noreply@example.com';
      update setting;
      ContractDocumentSettingService.clearCache();
      ContractEmailTemplateService.seedActiveRowForTest(
        ContractEmailTemplateService.TYPE_INVOICE,
        'InvoiceMail'
      );

      Invoice__c invoice = createConfirmedInvoice();
      InvoiceBoardDocumentService.SendPreviewDto preview = InvoiceBoardDocumentService.previewFromPreview(
        invoice.Id,
        'StandardInvoice',
        'InvoiceMail'
      );
      System.assertEquals(
        'noreply@example.com',
        preview.fromLabel,
        'Core 第7.10節: Fromは組織送信元の参照'
      );
      System.assertEquals(
        'board-doc@example.com',
        preview.toAddresses,
        'Core 第7.10節: 宛先の初期値は請求書スナップショット'
      );
      System.assertEquals(
        '',
        preview.subject,
        'テストは差し込みを飛ばす。本文を定数で埋めない'
      );
      System.assertNotEquals(null, preview.fileName);
      System.assert(preview.fileName.endsWith('.pdf'));
      System.assertEquals(
        InvoiceBoardDocumentService.ATTACHMENT_NEW,
        preview.attachmentId,
        'Core 第7.10節: Files 0件なら新しく発行する'
      );
    }
  }

  @IsTest
  static void sendFromPreview_ignoresDraftRecipients() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.InvoiceSendMode__c = 'PdfAndEmail';
      setting.InvoiceDefaultEmailTemplateApiName__c = 'InvoiceMail';
      setting.InvoiceOrgWideEmailAddress__c = 'noreply@example.com';
      update setting;
      ContractDocumentSettingService.clearCache();
      ContractEmailTemplateService.seedActiveRowForTest(
        ContractEmailTemplateService.TYPE_INVOICE,
        'InvoiceMail'
      );

      Invoice__c invoice = createConfirmedInvoice();
      InvoiceBoardDocumentService.SendDraftDto draft = new InvoiceBoardDocumentService.SendDraftDto();
      draft.toAddresses = 'not-an-email';
      draft.ccAddresses = 'also-invalid';
      draft.bccAddresses = 'still-invalid';
      draft.subject = '加筆件名';
      draft.body = '加筆本文';
      draft.fileName = 'custom-invoice.pdf';
      draft.attachmentId = InvoiceBoardDocumentService.ATTACHMENT_NEW;
      InvoiceBoardDocumentService.skipEmailSend = true;
      InvoiceBoardDocumentService.DocumentResultDto result;
      try {
        result = InvoiceBoardDocumentService.sendFromPreview(
          invoice.Id,
          'StandardInvoice',
          'InvoiceMail',
          token(invoice.Id),
          draft
        );
      } finally {
        InvoiceBoardDocumentService.skipEmailSend = false;
      }
      System.assertNotEquals(
        null,
        result,
        'Core 第7.10節: 請求の To／Cc／Bcc は下書きを使わずスナップショットで送る'
      );
      Invoice__c stored = [
        SELECT BillingEmailToSnapShot__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(
        'board-doc@example.com',
        stored.BillingEmailToSnapShot__c,
        'Core 第7.10節: プレビュー加筆は請求書スナップショットに書き戻さない'
      );
      InvoiceBoardDocumentService.SendPreviewDto preview = InvoiceBoardDocumentService.previewFromPreview(
        invoice.Id,
        'StandardInvoice',
        'InvoiceMail'
      );
      System.assertEquals(
        'board-doc@example.com',
        preview.toAddresses,
        'Core 第7.10節: 再送の宛先初期値はスナップショットであり、前回送付で直した宛先は使わない'
      );
    }
  }

  @IsTest
  static void boardDocument_rejectInvoiceOutsideContractService() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.InvoiceSendMode__c = 'PdfAndEmail';
      setting.InvoiceDefaultDocumentTemplateKey__c = 'StandardInvoice';
      update setting;
      ContractDocumentSettingService.clearCache();

      Invoice__c own = createConfirmedInvoice();
      Invoice__c other = createConfirmedInvoice();

      Boolean issuePreviewRejected = false;
      try {
        InvoiceBoardDocumentService.previewIssueFromPreview(
          other.Id,
          'StandardInvoice',
          own.ContractHistory__c
        );
      } catch (AuraHandledException ex) {
        issuePreviewRejected = true;
        System.assertEquals(
          InvoiceOpsController.SCOPE_MISMATCH_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(
        true,
        issuePreviewRejected,
        'Core 第7.7.3節: 契約サービスをまたいで発行プレビューできない'
      );

      Boolean issueRejected = false;
      try {
        InvoiceBoardDocumentService.issueFromPreview(
          other.Id,
          'StandardInvoice',
          token(other.Id),
          own.ContractHistory__c
        );
      } catch (AuraHandledException ex) {
        issueRejected = true;
        System.assertEquals(
          InvoiceOpsController.SCOPE_MISMATCH_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(
        true,
        issueRejected,
        'Core 第7.7.3節: 契約サービスをまたいで発行できない'
      );

      Boolean sendPreviewRejected = false;
      try {
        InvoiceBoardDocumentService.previewFromPreview(
          other.Id,
          'StandardInvoice',
          'InvoiceMail',
          null,
          own.ContractHistory__c
        );
      } catch (AuraHandledException ex) {
        sendPreviewRejected = true;
        System.assertEquals(
          InvoiceOpsController.SCOPE_MISMATCH_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(
        true,
        sendPreviewRejected,
        'Core 第7.7.3節: 契約サービスをまたいで送付プレビューできない'
      );

      Boolean sendRejected = false;
      try {
        InvoiceBoardDocumentService.sendFromPreview(
          other.Id,
          'StandardInvoice',
          'InvoiceMail',
          token(other.Id),
          null,
          own.ContractHistory__c
        );
      } catch (AuraHandledException ex) {
        sendRejected = true;
        System.assertEquals(
          InvoiceOpsController.SCOPE_MISMATCH_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(
        true,
        sendRejected,
        'Core 第7.7.3節: 契約サービスをまたいで送付できない'
      );
    }
  }

  private static Invoice__c createConfirmedInvoice() {
    return createConfirmedInvoice(InvoiceDeliveryMethodService.EMAIL);
  }

  private static Invoice__c createConfirmedInvoice(String deliveryMethod) {
    Account account = ContractTestDataFactory.insertAccount('Board Doc Account');
    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = account.Id,
      BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
      BillingEmailTo__c = 'board-doc@example.com',
      InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER,
      InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY,
      InvoiceDateDayOfMonth__c = 1,
      InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
      PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET,
      PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END,
      PaymentTermMonthOffset__c = 0,
      PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE);
    ContractTestDataFactory.applyRequiredFields(billingAccount);
    insert billingAccount;
    ContractService__c service = new ContractService__c(
      Name = 'Board Doc Service',
      Account__c = account.Id,
      BiilingAcccount__c = billingAccount.Id,
      TaxPercent__c = 0.1
    );
    insert service;
    ContractHistory__c history = new ContractHistory__c(
      ContractService__c = service.Id,
      Type__c = 'New',
      historystatus__c = 'Ordered',
      Version__c = 1
    );
    ContractTestDataFactory.applyRequiredFields(history);
    insert history;
    Invoice__c invoice = new Invoice__c(
      ContractService__c = service.Id,
      ContractHistory__c = history.Id,
      InvoiceDate__c = Date.today(),
      Amount__c = 1000,
      TaxAmount__c = 100,
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED,
      BillingEmailToSnapShot__c = 'board-doc@example.com',
      InvoiceDeliveryMethodSnapShot__c = deliveryMethod
    );
    ContractTestDataFactory.applyRequiredFields(invoice);
    Boolean previous = InvoiceTransactionStatusService.allowStatusWrite;
    InvoiceTransactionStatusService.allowStatusWrite = true;
    try {
      insert invoice;
    } finally {
      InvoiceTransactionStatusService.allowStatusWrite = previous;
    }
    return invoice;
  }

  private static String token(Id invoiceId) {
    Invoice__c invoice = [
      SELECT LastModifiedDate
      FROM Invoice__c
      WHERE Id = :invoiceId
    ];
    return ContractOptimisticLockUtil.toToken(invoice.LastModifiedDate);
  }
}
