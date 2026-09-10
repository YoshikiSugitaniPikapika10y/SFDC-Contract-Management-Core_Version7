@IsTest
private class InvoiceBoardDocumentServiceTest {
  @TestSetup
  static void setup() {
    ContractTestDataFactory.initTestContext();
    ContractTestDataFactory.ensureOrgAccountingPolicy();
  }

  @IsTest
  static void previewIssueFromPreview_returnsPatternFileNameWithoutSaving() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.InvoiceSendMode__c = 'PdfOnly';
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
        'StandardInvoice',
        invoice.ContractHistory__c
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
  static void previewIssueFromPreview_blankTemplateKey_throwsJapanese() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.InvoiceSendMode__c = 'PdfOnly';
      update setting;
      ContractDocumentSettingService.clearCache();

      Invoice__c invoice = createConfirmedInvoice();
      Boolean thrown = false;
      try {
        InvoiceBoardDocumentService.previewIssueFromPreview(
          invoice.Id,
          null,
          invoice.ContractHistory__c
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '請求書の発行ファイル名を取得できませんでした。 ' +
            ContractDocumentSettingService.MISSING_DEFAULT_DOCUMENT_MESSAGE,
          ex.getMessage(),
          'Core 第7.10節・第11.3.2節: キー空は発行できない。既定印でもカタログ先頭でも埋めない'
        );
      }
      System.assertEquals(true, thrown);
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
        InvoiceBoardDocumentService.previewIssueFromPreview(
          invoice.Id,
          'StandardInvoice'
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          InvoiceBoardDocumentService.UNUSED_BLOCK_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
      thrown = false;
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
  static void issueFromPreview_rejectsDraft() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.InvoiceSendMode__c = 'PdfOnly';
      update setting;
      ContractDocumentSettingService.clearCache();

      Invoice__c invoice = createDraftInvoice();
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
          InvoiceBoardDocumentService.DRAFT_BLOCK_MESSAGE,
          ex.getMessage(),
          'Core 第7.10節: 確定済みの請求だけ発行できる'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void sendFromPreview_blankAttachment_throws() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.InvoiceSendMode__c = 'PdfAndEmail';
      setting.InvoiceOrgWideEmailAddress__c = ContractTestDataFactory.requireVerifiedOrgWideAddress();
      update setting;
      ContractDocumentSettingService.clearCache();
      ContractEmailTemplateService.seedActiveRowForTest(
        ContractEmailTemplateService.TYPE_INVOICE,
        'InvoiceMail'
      );

      Invoice__c invoice = createConfirmedInvoice();
      InvoiceBoardDocumentService.SendDraftDto draft = new InvoiceBoardDocumentService.SendDraftDto();
      draft.subject = '件名';
      draft.body = '本文';
      draft.fileName = 'invoice-send.pdf';
      draft.attachmentId = null;
      InvoiceBoardDocumentService.skipEmailSend = true;
      Boolean thrown = false;
      try {
        InvoiceBoardDocumentService.sendFromPreview(
          invoice.Id,
          'StandardInvoice',
          'InvoiceMail',
          token(invoice.Id),
          draft
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          InvoiceBoardDocumentService.MISSING_ATTACHMENT_MESSAGE,
          ex.getMessage(),
          'Core 第7.10節: 未選択では送れない'
        );
      } finally {
        InvoiceBoardDocumentService.skipEmailSend = false;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void sendFromPreview_blankFileName_throws() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.InvoiceSendMode__c = 'PdfAndEmail';
      setting.InvoiceOrgWideEmailAddress__c = ContractTestDataFactory.requireVerifiedOrgWideAddress();
      update setting;
      ContractDocumentSettingService.clearCache();
      ContractEmailTemplateService.seedActiveRowForTest(
        ContractEmailTemplateService.TYPE_INVOICE,
        'InvoiceMail'
      );

      Invoice__c invoice = createConfirmedInvoice();
      InvoiceBoardDocumentService.SendDraftDto draft = new InvoiceBoardDocumentService.SendDraftDto();
      draft.fileName = '';
      draft.attachmentId = InvoiceBoardDocumentService.ATTACHMENT_NEW;
      InvoiceBoardDocumentService.skipEmailSend = true;
      Boolean thrown = false;
      try {
        InvoiceBoardDocumentService.sendFromPreview(
          invoice.Id,
          'StandardInvoice',
          'InvoiceMail',
          token(invoice.Id),
          draft
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          InvoiceBoardDocumentService.MISSING_ATTACHMENT_NAME_MESSAGE,
          ex.getMessage(),
          'Core 第7.10節: 添付ファイル名が空では送れない'
        );
      } finally {
        InvoiceBoardDocumentService.skipEmailSend = false;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void previewIssueFromPreview_rejectsCancelled() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = createConfirmedInvoice();
      Boolean previousStatus = InvoiceTransactionStatusService.allowStatusWrite;
      Boolean previousLock = InvoiceLockUtil.allowLockedStatusWrite;
      InvoiceTransactionStatusService.allowStatusWrite = true;
      InvoiceLockUtil.allowLockedStatusWrite = true;
      try {
        invoice.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CANCELLED;
        update invoice;
      } finally {
        InvoiceTransactionStatusService.allowStatusWrite = previousStatus;
        InvoiceLockUtil.allowLockedStatusWrite = previousLock;
      }
      Boolean thrown = false;
      try {
        InvoiceBoardDocumentService.previewIssueFromPreview(invoice.Id, 'StandardInvoice');
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          InvoiceBoardDocumentService.CANCELLED_BLOCK_MESSAGE,
          ex.getMessage(),
          'Core 第7.10節: 取消済み請求は通常発行の対象にしない'
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
      setting.InvoiceOrgWideEmailAddress__c = ContractTestDataFactory.requireVerifiedOrgWideAddress();
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
        System.assertEquals(
          ContractEmailTemplateService.MISSING_API_NAME_MESSAGE,
          ex.getMessage(),
          '仕様: Core 第11.3.2節 カタログ無しでは送付しない'
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
      setting.InvoiceOrgWideEmailAddress__c = ContractTestDataFactory.requireVerifiedOrgWideAddress();
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
      Boolean previousLock = InvoiceLockUtil.allowLockedStatusWrite;
      InvoiceLockUtil.allowLockedStatusWrite = true;
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
        InvoiceLockUtil.allowLockedStatusWrite = previousLock;
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
  static void sendFromPreview_scoped_reusesLockedInvoiceWithoutCount() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.InvoiceSendMode__c = 'PdfAndEmail';
      setting.InvoiceOrgWideEmailAddress__c = ContractTestDataFactory.requireVerifiedOrgWideAddress();
      update setting;
      ContractDocumentSettingService.clearCache();
      ContractEmailTemplateService.seedActiveRowForTest(
        ContractEmailTemplateService.TYPE_INVOICE,
        'InvoiceMail'
      );

      Invoice__c created = createConfirmedInvoice();
      Invoice__c loaded = [
        SELECT
          Id,
          ContractHistory__c,
          ContractService__c,
          InvoiceTransactionStatus__c,
          DeliveryStatus__c,
          SentDate__c,
          SystemIntegrationDate__c,
          BillingEmailToSnapShot__c,
          BillingEmailCcSnapShot__c,
          BillingEmailBccSnapShot__c,
          InvoiceDeliveryMethodSnapShot__c,
          Amount__c,
          TaxAmount__c,
          TaxInclusiveAmount__c
        FROM Invoice__c
        WHERE Id = :created.Id
      ];
      InvoiceBoardDocumentService.SendDraftDto draft = new InvoiceBoardDocumentService.SendDraftDto();
      draft.toAddresses = loaded.BillingEmailToSnapShot__c;
      draft.ccAddresses = '';
      draft.bccAddresses = '';
      draft.subject = '件名';
      draft.body = '本文';
      draft.fileName = 'invoice-send-scope.pdf';
      draft.attachmentId = InvoiceBoardDocumentService.ATTACHMENT_NEW;
      InvoiceBoardDocumentService.skipEmailSend = true;
      Boolean previousLock = InvoiceLockUtil.allowLockedStatusWrite;
      InvoiceLockUtil.allowLockedStatusWrite = true;
      try {
        Test.startTest();
        InvoiceBoardDocumentService.sendFromPreview(
          loaded.Id,
          'StandardInvoice',
          'InvoiceMail',
          null,
          draft
        );
        Integer beforeScoped = Limits.getQueries();
        InvoiceBoardDocumentService.DocumentResultDto scoped = InvoiceBoardDocumentService.sendFromPreview(
          loaded.Id,
          'StandardInvoice',
          'InvoiceMail',
          null,
          draft,
          loaded.ContractHistory__c
        );
        Integer usedScoped = Limits.getQueries() - beforeScoped;
        Integer beforeIdOnly = Limits.getQueries();
        InvoiceBoardDocumentService.DocumentResultDto idOnly = InvoiceBoardDocumentService.sendFromPreview(
          loaded.Id,
          'StandardInvoice',
          'InvoiceMail',
          null,
          draft
        );
        Integer usedIdOnly = Limits.getQueries() - beforeIdOnly;
        Test.stopTest();

        System.assertEquals(
          usedIdOnly,
          usedScoped,
          'Core 第12.4節・第7.10節: 範囲COUNTのあと行ロックで同じ請求を取り直さない'
        );
        System.assertNotEquals(
          null,
          scoped.sentAt,
          'Core 第7.10節: 送付結果は変えない'
        );
        System.assertEquals(idOnly.documentTemplateKey, scoped.documentTemplateKey);
        System.assertEquals(
          InvoiceDeliveryMethodService.EMAIL,
          loaded.InvoiceDeliveryMethodSnapShot__c,
          '開発ルール第13節: 入口はSOQL行の届け方スナップショットを読む'
        );
        System.assertEquals(
          ContractTestDataFactory.TENANT_BILLING_EMAIL_TO,
          loaded.BillingEmailToSnapShot__c,
          '開発ルール第13節: 入口はSOQL行のToスナップショットを読む'
        );
        System.assertEquals(
          InvoiceTransactionStatusService.TX_CONFIRMED,
          loaded.InvoiceTransactionStatus__c,
          '開発ルール第13節: 入口はSOQL行の取引状態を読む'
        );
      } finally {
        InvoiceLockUtil.allowLockedStatusWrite = previousLock;
        InvoiceBoardDocumentService.skipEmailSend = false;
      }
    }
  }

  @IsTest
  static void sendFromPreview_jsonDraftKeepsFileName() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.InvoiceSendMode__c = 'PdfAndEmail';
      setting.InvoiceOrgWideEmailAddress__c = ContractTestDataFactory.requireVerifiedOrgWideAddress();
      update setting;
      ContractDocumentSettingService.clearCache();
      ContractEmailTemplateService.seedActiveRowForTest(
        ContractEmailTemplateService.TYPE_INVOICE,
        'InvoiceMail'
      );

      Invoice__c invoice = createConfirmedInvoice();
      InvoiceBoardDocumentService.SendDraftDto draft = (InvoiceBoardDocumentService.SendDraftDto) JSON.deserialize(
        '{"fileName":"from-json.pdf","subject":"件名","body":"本文","attachmentId":"NEW","toAddresses":"","ccAddresses":"","bccAddresses":""}',
        InvoiceBoardDocumentService.SendDraftDto.class
      );
      System.assertEquals(
        'from-json.pdf',
        draft.fileName,
        'Core 第7.10節: LWC JSONの件名・本文・添付名を受け取る'
      );
      InvoiceBoardDocumentService.skipEmailSend = true;
      Boolean previousLock = InvoiceLockUtil.allowLockedStatusWrite;
      InvoiceLockUtil.allowLockedStatusWrite = true;
      try {
        InvoiceBoardDocumentService.sendFromPreview(
          invoice.Id,
          'StandardInvoice',
          'InvoiceMail',
          token(invoice.Id),
          draft
        );
      } finally {
        InvoiceLockUtil.allowLockedStatusWrite = previousLock;
        InvoiceBoardDocumentService.skipEmailSend = false;
      }
    }
  }

  @IsTest
  static void sendFromPreview_blankToken_sends() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.InvoiceSendMode__c = 'PdfAndEmail';
      setting.InvoiceOrgWideEmailAddress__c = ContractTestDataFactory.requireVerifiedOrgWideAddress();
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
      Boolean previousLock = InvoiceLockUtil.allowLockedStatusWrite;
      InvoiceLockUtil.allowLockedStatusWrite = true;
      InvoiceBoardDocumentService.DocumentResultDto result;
      try {
        result = InvoiceBoardDocumentService.sendFromPreview(
          invoice.Id,
          'StandardInvoice',
          'InvoiceMail',
          null,
          draft
        );
      } finally {
        InvoiceLockUtil.allowLockedStatusWrite = previousLock;
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
  static void issueFromPreview_scoped_reusesLockedInvoiceWithoutCount() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.InvoiceSendMode__c = 'PdfOnly';
      update setting;
      ContractDocumentSettingService.clearCache();

      Invoice__c created = createConfirmedInvoice();
      Invoice__c loaded = [
        SELECT
          Id,
          Name,
          ContractHistory__c,
          ContractService__c,
          InvoiceTransactionStatus__c,
          InvoiceDate__c,
          PaymentScheduledDate__c,
          BillingAddresseeSnapShot__c,
          Amount__c,
          TaxAmount__c,
          TaxInclusiveAmount__c
        FROM Invoice__c
        WHERE Id = :created.Id
      ];

      Test.startTest();
      InvoiceBoardDocumentService.issueFromPreview(
        loaded.Id,
        'StandardInvoice',
        null
      );
      Integer beforeScoped = Limits.getQueries();
      InvoiceBoardDocumentService.DocumentResultDto scoped = InvoiceBoardDocumentService.issueFromPreview(
        loaded.Id,
        'StandardInvoice',
        null,
        loaded.ContractHistory__c
      );
      Integer usedScoped = Limits.getQueries() - beforeScoped;
      Integer beforeIdOnly = Limits.getQueries();
      InvoiceBoardDocumentService.DocumentResultDto idOnly = InvoiceBoardDocumentService.issueFromPreview(
        loaded.Id,
        'StandardInvoice',
        null
      );
      Integer usedIdOnly = Limits.getQueries() - beforeIdOnly;
      Test.stopTest();

      System.assertEquals(
        usedIdOnly,
        usedScoped,
        'Core 第12.4節・第7.10節: 範囲COUNTのあと行ロックで同じ請求を取り直さない'
      );
      System.assertNotEquals(
        null,
        scoped.fileName,
        'Core 第7.10節: 発行PDFの結果は変えない'
      );
      System.assertEquals(
        idOnly.documentTemplateKey,
        scoped.documentTemplateKey
      );
      System.assertEquals(
        InvoiceTransactionStatusService.TX_CONFIRMED,
        loaded.InvoiceTransactionStatus__c,
        '開発ルール第13節: 入口はSOQL行の確定状態を読む'
      );
      System.assertNotEquals(
        null,
        loaded.Amount__c,
        '開発ルール第13節: 入口はSOQL行の税抜を読む'
      );
    }
  }

  @IsTest
  static void previewFromPreview_returnsSnapshotRecipientsAndFrom() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.InvoiceSendMode__c = 'PdfAndEmail';
      String orgSender = ContractTestDataFactory.requireVerifiedOrgWideAddress();
      setting.InvoiceOrgWideEmailAddress__c = orgSender;
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
      System.assert(
        preview.fromLabel != null && preview.fromLabel.contains(orgSender),
        'Core 第7.10節: Fromは組織送信元の参照'
      );
      System.assertEquals(
        ContractTestDataFactory.TENANT_BILLING_EMAIL_TO,
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
      setting.InvoiceOrgWideEmailAddress__c = ContractTestDataFactory.requireVerifiedOrgWideAddress();
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
      Boolean previousLock = InvoiceLockUtil.allowLockedStatusWrite;
      InvoiceLockUtil.allowLockedStatusWrite = true;
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
        InvoiceLockUtil.allowLockedStatusWrite = previousLock;
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
        ContractTestDataFactory.TENANT_BILLING_EMAIL_TO,
        stored.BillingEmailToSnapShot__c,
        'Core 第7.10節: プレビュー加筆は請求書スナップショットに書き戻さない'
      );
      InvoiceBoardDocumentService.SendPreviewDto preview = InvoiceBoardDocumentService.previewFromPreview(
        invoice.Id,
        'StandardInvoice',
        'InvoiceMail'
      );
      System.assertEquals(
        ContractTestDataFactory.TENANT_BILLING_EMAIL_TO,
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
      update setting;
      ContractDocumentSettingService.clearCache();

      Invoice__c own = createConfirmedInvoice();
      Test.startTest();
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
      Test.stopTest();
    }
  }

  private static Invoice__c createConfirmedInvoice() {
    return createBoardInvoice(InvoiceDeliveryMethodService.EMAIL, true);
  }

  private static Invoice__c createConfirmedInvoice(String deliveryMethod) {
    return createBoardInvoice(deliveryMethod, true);
  }

  private static Invoice__c createDraftInvoice() {
    return createBoardInvoice(InvoiceDeliveryMethodService.EMAIL, false);
  }

  private static Invoice__c createBoardInvoice(
    String deliveryMethod,
    Boolean confirmed
  ) {
    Account account = ContractTestDataFactory.insertAccount('Board Doc Account');
    ContractService__c service = ContractTestDataFactory.insertContractService(
      account.Id,
      'Board Doc Service'
    );
    BillingAccount__c billingAccount = [
      SELECT Id, BillingEmailTo__c
      FROM BillingAccount__c
      WHERE Id = :service.BiilingAcccount__c
    ];
    billingAccount.InvoiceDeliveryMethod__c = deliveryMethod;
    update billingAccount;
    ContractHistory__c history = new ContractHistory__c(
      Name = 'Board Doc History',
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
      'Board Doc Product ' + String.valueOf(Crypto.getRandomInteger())
    );
    product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
    ContractTestDataFactory.insertProduct(product);
    ContractProduct__c contractProduct = new ContractProduct__c(
      ContractHistory__c = history.Id,
      Account__c = account.Id,
      Product__c = product.Id,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      Amount__c = 1000,
      StartDate__c = history.CurrentTermStartDate__c,
      Enddate__c = history.CurrentTermEndDate__c,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME,
      Type__c = 'New',
      RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME
    );
    ContractTestDataFactory.applyRequiredFields(contractProduct);
    contractProduct.Amount__c = 1000;
    insert contractProduct;
    history.historystatus__c = 'Ordered';
    update history;
    Invoice__c invoice = new Invoice__c(
      ContractService__c = service.Id,
      ContractHistory__c = history.Id,
      InvoiceDate__c = Date.today(),
      Amount__c = 1000,
      TaxAmount__c = 100,
      BillingAccountSnapShot__c = billingAccount.Id,
      BillingEmailToSnapShot__c = billingAccount.BillingEmailTo__c,
      InvoiceDeliveryMethodSnapShot__c = deliveryMethod
    );
    ContractTestDataFactory.applyInvoiceInsertSeedStatuses(invoice);
    if (confirmed == true) {
      invoice.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED;
      invoice.SystemIntegrationDate__c = InvoiceTransactionStatusService.organizationToday();
    }
    invoice.DeliveryStatus__c = InvoiceDeliveryMethodService.EMAIL.equals(
        deliveryMethod
      )
      ? InvoiceTransactionStatusService.DELIVERY_UNSENT
      : InvoiceTransactionStatusService.DELIVERY_NOT_APPLICABLE;
    ContractTestDataFactory.insertAllowingInvoiceStatus(invoice);
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
