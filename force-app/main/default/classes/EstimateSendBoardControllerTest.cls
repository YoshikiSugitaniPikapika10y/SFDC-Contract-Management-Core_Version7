@IsTest
private class EstimateSendBoardControllerTest {
  @TestSetup
  static void setup() {
    ContractTestDataFactory.initTestContext();
    ContractTestDataFactory.ensureOrgAccountingPolicy();
    ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
    setting.EstimateSendMode__c = 'PdfAndEmail';
    setting.EstimateOrgWideEmailAddress__c = ContractTestDataFactory.requireVerifiedOrgWideAddress();
    update setting;
    ContractDocumentSettingService.clearCache();
  }

  @IsTest
  static void contextAndList_returnConfiguredEstimate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractHistory__c history = createEstimate('board@example.com');

      EstimateSendBoardController.BoardContextDto context = EstimateSendBoardController.getBoardContext();
      System.assertEquals(true, context.canSend);
      System.assertEquals(true, context.featureEnabled);
      System.assertEquals(500, context.listLimit);
      System.assertEquals('StandardEstimate', context.defaultDocumentTemplateKey);
      System.assert(
        !context.documentTemplateOptions.isEmpty(),
        'Estimate帳票テンプレートが返ること'
      );

      EstimateSendBoardController.EstimateRowDto row = EstimateSendBoardController.getRecordActionEstimate(
        history.Id
      );
      System.assertEquals(history.Id, row.historyId);
      System.assertEquals(true, row.sendable);
      System.assertEquals(
        'board@example.com',
        row.toAddresses,
        'Core 第4.8節: 宛先の正は見積送付先'
      );
      System.assertEquals(
        currentToken(history.Id),
        row.lastModifiedToken
      );
    }
  }

  @IsTest
  static void getRecordActionEstimate_rejectsNonEstimateWithJapaneseStatus() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractHistory__c history = createEstimate('ordered@example.com');
      insertLine(history);
      history.historystatus__c = 'Ordered';
      update history;

      Boolean thrown = false;
      try {
        EstimateSendBoardController.getRecordActionEstimate(history.Id);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          EstimateSendBoardController.ESTIMATE_STATUS_REQUIRED_MESSAGE,
          ex.getMessage()
        );
        System.assertEquals(
          false,
          EstimateSendBoardController.ESTIMATE_STATUS_REQUIRED_MESSAGE.contains(
            'Estimate'
          ),
          'Core 第0.1節: 人が見る拒否文に Estimate と出さない'
        );
        System.assertEquals(
          'ステータスが見積の契約履歴のみ操作できます。',
          EstimateSendBoardController.ESTIMATE_STATUS_REQUIRED_MESSAGE,
          'Core 第0.1節: Estimate の画面表示は見積'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void sendEstimate_recordsTimestampHistoryAndFile() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractHistory__c history = createEstimate('first@example.com');
      EstimateSendBoardController.skipEmailSend = true;
      ContractEmailTemplateService.seedActiveRowForTest(
        ContractEmailTemplateService.TYPE_ESTIMATE,
        'EstimateMail'
      );
      String token = currentToken(history.Id);

      EstimateSendBoardController.SendDraftDto draft = new EstimateSendBoardController.SendDraftDto();
      draft.toAddresses = 'not-an-email';
      draft.fileName = 'estimate-send.pdf';
      draft.attachmentId = EstimateSendBoardController.ATTACHMENT_NEW;
      EstimateSendBoardController.ActionResultDto result = EstimateSendBoardController.sendEstimateFromRecordPage(
        history.Id,
        'StandardEstimate',
        'EstimateMail',
        token,
        draft
      );

      ContractHistory__c updated = [
        SELECT EstimateSentAt__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertNotEquals(
        null,
        updated.EstimateSentAt__c,
        'Core 第4.8節: 送付成功時に見積送付日を設定する'
      );
      System.assertEquals(updated.EstimateSentAt__c, result.sentAt);
      EstimateSendBoardController.skipEmailSend = false;
    }
  }

  @IsTest
  static void sendEstimateFromRecordPage_blankToken_sends() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractHistory__c history = createEstimate('blank-token@example.com');
      EstimateSendBoardController.skipEmailSend = true;
      ContractEmailTemplateService.seedActiveRowForTest(
        ContractEmailTemplateService.TYPE_ESTIMATE,
        'EstimateMail'
      );

      EstimateSendBoardController.SendDraftDto draft = new EstimateSendBoardController.SendDraftDto();
      draft.toAddresses = 'not-an-email';
      draft.fileName = 'estimate-send.pdf';
      draft.attachmentId = EstimateSendBoardController.ATTACHMENT_NEW;
      EstimateSendBoardController.ActionResultDto result = EstimateSendBoardController.sendEstimateFromRecordPage(
        history.Id,
        'StandardEstimate',
        'EstimateMail',
        null,
        draft
      );

      ContractHistory__c updated = [
        SELECT EstimateSentAt__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertNotEquals(
        null,
        updated.EstimateSentAt__c,
        'Core 第4.3.12節: 見積の個別送付は比較なし'
      );
      System.assertEquals(updated.EstimateSentAt__c, result.sentAt);
      EstimateSendBoardController.skipEmailSend = false;
    }
  }

  @IsTest
  static void recordAction_loadsAndSendsSingleEstimate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractHistory__c history = createEstimate('record-action@example.com');

      EstimateSendBoardController.EstimateRowDto state = EstimateSendBoardController.getRecordActionEstimate(
        history.Id
      );
      System.assertEquals(history.Id, state.historyId);
      System.assertEquals(true, state.sendable);
      System.assertEquals('record-action@example.com', state.toAddresses);

      EstimateSendBoardController.skipEmailSend = true;
      ContractEmailTemplateService.seedActiveRowForTest(
        ContractEmailTemplateService.TYPE_ESTIMATE,
        'EstimateMail'
      );
      EstimateSendBoardController.SendDraftDto draft = new EstimateSendBoardController.SendDraftDto();
      draft.toAddresses = 'record-action@example.com';
      draft.fileName = 'estimate-send.pdf';
      draft.attachmentId = EstimateSendBoardController.ATTACHMENT_NEW;
      EstimateSendBoardController.sendEstimateFromRecordPage(
        history.Id,
        'StandardEstimate',
        'EstimateMail',
        state.lastModifiedToken,
        draft
      );
      EstimateSendBoardController.skipEmailSend = false;

      ContractHistory__c updated = [
        SELECT EstimateSentAt__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertNotEquals(
        null,
        updated.EstimateSentAt__c,
        'Core 第4.8節: 送付成功時に見積送付日を設定する'
      );
    }
  }

  @IsTest
  static void previewEstimateFromRecordPage_returnsSendContactAndSelfFrom() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractHistory__c history = createEstimate('preview@example.com');
      history.EstimateIssueDate__c = Date.newInstance(2026, 3, 15);
      update history;
      ContractEmailTemplateService.seedActiveRowForTest(
        ContractEmailTemplateService.TYPE_ESTIMATE,
        'EstimateMail'
      );
      EstimateSendBoardController.SendPreviewDto preview = EstimateSendBoardController.previewEstimateFromRecordPage(
        history.Id,
        'StandardEstimate',
        'EstimateMail'
      );
      System.assertEquals(
        UserInfo.getUserEmail(),
        preview.fromLabel,
        'Core 第4.8節: Fromの初期値は自分'
      );
      System.assertEquals(
        EstimateSendBoardController.FROM_SELF,
        preview.fromChoice
      );
      System.assertEquals(
        'preview@example.com',
        preview.toAddresses,
        'Core 第4.8節: 初期Toは見積送付先のメール'
      );
      System.assertEquals(
        null,
        preview.ccAddresses,
        'Core 第4.8節: 初期Ccは空'
      );
      System.assertEquals(
        null,
        preview.bccAddresses,
        'Core 第4.8節: 初期Bccは空'
      );
      System.assertEquals(
        '',
        preview.subject,
        'テストは差し込みを飛ばす。本文を定数で埋めない'
      );
      System.assertEquals(
        'StandardEstimate_送付テスト見積_20260315.pdf',
        preview.fileName,
        'Core 第11.3.2節: 見積のファイル名日付は発行日'
      );
      System.assertEquals(
        EstimateSendBoardController.ATTACHMENT_NEW,
        preview.attachmentId,
        'Core 第7.10節: Files 0件なら新しく発行する'
      );
    }
  }

  @IsTest
  static void sendEstimateFromRecordPage_ignoresDraftTo() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractHistory__c history = createEstimate('master-to@example.com');
      ContractEmailTemplateService.seedActiveRowForTest(
        ContractEmailTemplateService.TYPE_ESTIMATE,
        'EstimateMail'
      );
      EstimateSendBoardController.SendDraftDto draft = new EstimateSendBoardController.SendDraftDto();
      draft.toAddresses = 'not-an-email';
      draft.ccAddresses = '';
      draft.bccAddresses = '';
      draft.subject = '加筆件名';
      draft.body = '加筆本文';
      draft.fileName = 'custom-estimate.pdf';
      draft.attachmentId = EstimateSendBoardController.ATTACHMENT_NEW;
      EstimateSendBoardController.skipEmailSend = true;
      EstimateSendBoardController.ActionResultDto result;
      try {
        result = EstimateSendBoardController.sendEstimateFromRecordPage(
          history.Id,
          'StandardEstimate',
          'EstimateMail',
          currentToken(history.Id),
          draft
        );
      } finally {
        EstimateSendBoardController.skipEmailSend = false;
      }
      ContractHistory__c sent = [
        SELECT EstimateSentAt__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertNotEquals(
        null,
        sent.EstimateSentAt__c,
        'Core 第4.8節: 送付成功時に見積送付日を設定する'
      );
      ContractHistory__c storedHistory = [
        SELECT ContractService__r.BiilingAcccount__r.BillingEmailTo__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals(
        'master-to@example.com',
        storedHistory.ContractService__r.BiilingAcccount__r.BillingEmailTo__c,
        'Core 第7.10節: プレビュー加筆は請求アカウントに書き戻さない'
      );
      EstimateSendBoardController.SendPreviewDto preview = EstimateSendBoardController.previewEstimateFromRecordPage(
        history.Id,
        'StandardEstimate',
        'EstimateMail'
      );
      System.assertEquals(
        'master-to@example.com',
        preview.toAddresses,
        'Core 第4.8節: 再送の宛先初期値は見積送付先であり、前回送付で直した宛先は使わない'
      );
    }
  }

  @IsTest
  static void sendEstimate_rejectsMissingTo() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractHistory__c history = createEstimate(null);
      try {
        EstimateSendBoardController.sendEstimateFromRecordPage(
          history.Id,
          'StandardEstimate',
          null,
          currentToken(history.Id)
        );
        System.assert(false, '例外が必要');
      } catch (AuraHandledException ex) {
        System.assertEquals(
          EstimateSendBoardController.MISSING_TO_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(
        null,
        [
          SELECT EstimateSentAt__c
          FROM ContractHistory__c
          WHERE Id = :history.Id
        ]
        .EstimateSentAt__c,
        'Core 第4.8節: 送れなければ送付日を書かない'
      );
    }
  }

  @IsTest
  static void sendEstimateFromRecordPage_rejectsUnstampedFile() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractHistory__c history = createEstimate('to@example.com');
      ContractEmailTemplateService.seedActiveRowForTest(
        ContractEmailTemplateService.TYPE_ESTIMATE,
        'EstimateMail'
      );
      ContentVersion handUpload = new ContentVersion(
        Title = 'hand-upload',
        PathOnClient = 'hand-upload.pdf',
        VersionData = Blob.valueOf('hand')
      );
      insert handUpload;
      Id documentId = [
        SELECT ContentDocumentId
        FROM ContentVersion
        WHERE Id = :handUpload.Id
      ]
      .ContentDocumentId;
      insert new ContentDocumentLink(
        ContentDocumentId = documentId,
        LinkedEntityId = history.Id,
        ShareType = 'V',
        Visibility = 'AllUsers'
      );
      EstimateSendBoardController.SendDraftDto draft = new EstimateSendBoardController.SendDraftDto();
      draft.toAddresses = 'to@example.com';
      draft.subject = '件名';
      draft.body = '本文';
      draft.fileName = 'hand-upload.pdf';
      draft.attachmentId = String.valueOf(documentId);
      try {
        EstimateSendBoardController.sendEstimateFromRecordPage(
          history.Id,
          'StandardEstimate',
          'EstimateMail',
          currentToken(history.Id),
          draft
        );
        System.assert(false, '例外が必要');
      } catch (AuraHandledException ex) {
        System.assert(
          ex.getMessage().contains('添付ファイルを選択'),
          'Core 第7.10節: 手アップロードは送れない'
        );
      }
    }
  }

  @IsTest
  static void sendEstimateFromRecordPage_rejectsOlderIssuedFile() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractHistory__c history = createEstimate('to@example.com');
      ContractEmailTemplateService.seedActiveRowForTest(
        ContractEmailTemplateService.TYPE_ESTIMATE,
        'EstimateMail'
      );
      Id olderIssuedId = insertIssuedFile(history.Id, 'older-issued');
      insertIssuedFile(history.Id, 'newer-issued');
      EstimateSendBoardController.SendDraftDto draft = new EstimateSendBoardController.SendDraftDto();
      draft.toAddresses = 'to@example.com';
      draft.subject = '件名';
      draft.body = '本文';
      draft.fileName = 'older-issued.pdf';
      draft.attachmentId = String.valueOf(olderIssuedId);
      try {
        EstimateSendBoardController.sendEstimateFromRecordPage(
          history.Id,
          'StandardEstimate',
          'EstimateMail',
          currentToken(history.Id),
          draft
        );
        System.assert(false, '例外が必要');
      } catch (AuraHandledException ex) {
        System.assert(
          ex.getMessage().contains('添付ファイルを選択'),
          'Core 第7.10節: 古い発行は送れない'
        );
      }
    }
  }

  @IsTest
  static void parseAddresses_splitsCommaOnlyAndRejectsInvalid() {
    List<String> parsed = EstimateSendBoardController.parseAddresses(
      'a@example.com, b@example.com, A@example.com',
      'Cc'
    );
    System.assertEquals(2, parsed.size(), '大文字小文字を無視して重複排除');
    System.assertEquals('a@example.com', parsed[0]);
    System.assertEquals('b@example.com', parsed[1]);
    List<String> emptySep = EstimateSendBoardController.parseAddresses(
      'a@example.com,, b@example.com',
      'Cc'
    );
    System.assertEquals(2, emptySep.size(), '空の区切りは無視する');
    try {
      EstimateSendBoardController.parseAddresses(
        'a@example.com; b@example.com',
        'Cc'
      );
      System.assert(false, 'セミコロンは区切りではない');
    } catch (AuraHandledException ex) {
      System.assert(ex.getMessage().contains('不正なメールアドレス'));
    }
    try {
      EstimateSendBoardController.parseAddresses('not-an-email', 'Cc');
      System.assert(false, '不正アドレスは拒否');
    } catch (AuraHandledException ex) {
      System.assert(ex.getMessage().contains('不正なメールアドレス'));
    }
    try {
      EstimateSendBoardController.parseAddresses(
        'a@example.com,' + 'x'.repeat(250) + '@example.com',
        'Cc'
      );
      System.assert(false, '255文字超は拒否');
    } catch (AuraHandledException ex) {
      System.assert(ex.getMessage().contains('255文字以内'));
    }
  }

  @IsTest
  static void sendEstimateFromRecordPage_requiresSendPermission() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractHistory__c history = createEstimate('perm@example.com');
      EstimateSendBoardController.skipEmailSend = true;
      ContractEmailTemplateService.seedActiveRowForTest(
        ContractEmailTemplateService.TYPE_ESTIMATE,
        'EstimateMail'
      );
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.SEND_ESTIMATE => false
      };
      try {
        EstimateSendBoardController.SendDraftDto draft = new EstimateSendBoardController.SendDraftDto();
        draft.fileName = 'estimate-send.pdf';
        draft.attachmentId = EstimateSendBoardController.ATTACHMENT_NEW;
        EstimateSendBoardController.sendEstimateFromRecordPage(
          history.Id,
          'StandardEstimate',
          null,
          currentToken(history.Id),
          draft
        );
        System.assert(false, '権限05が無いときは送れない');
      } catch (AuraHandledException ex) {
        System.assertEquals(
          '見積を送る権限がありません。',
          ex.getMessage()
        );
      } finally {
        ContractPermissionUtil.testOverrides = null;
        EstimateSendBoardController.skipEmailSend = false;
      }
    }
  }

  @IsTest
  static void getBoardContext_initialSelectionUsesCatalogDefault() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      EstimateSendBoardController.BoardContextDto context = EstimateSendBoardController.getBoardContext();
      System.assertEquals(
        'StandardEstimate',
        context.defaultDocumentTemplateKey,
        'Core 第11.3.2節: 有効な既定がちょうど1つなら初期選択'
      );
      System.assertEquals(
        false,
        context.documentTemplateOptions.isEmpty(),
        'カタログ候補は出す'
      );
    }
  }

  private static ContractHistory__c createEstimate(String toAddress) {
    Account account = ContractTestDataFactory.insertAccount('送付テスト取引先');
    BillingAccount__c billing = ContractTestDataFactory.insertBillingAccount(
      account.Id
    );
    if (String.isNotBlank(toAddress)) {
      billing.BillingEmailTo__c = toAddress;
      update billing;
    }

    Contact sendContact;
    if (String.isNotBlank(toAddress)) {
      sendContact = ContractTestDataFactory.insertContact(account.Id, '見積送付先');
      sendContact.Email = toAddress;
      update sendContact;
    }

    ContractService__c service = new ContractService__c(
      Name = '送付テストサービス',
      Account__c = account.Id,
      BiilingAcccount__c = billing.Id,
      TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
    );
    ContractTestDataFactory.applyRequiredFields(service);
    insert service;

    ContractHistory__c history = new ContractHistory__c(
      Name = 'EST-SEND-' + String.valueOf(Crypto.getRandomInteger()).replace('-', ''),
      ContractService__c = service.Id,
      Type__c = 'New',
      historystatus__c = 'Estimate',
      Version__c = 1,
      CurrentTermStartDate__c = Date.today(),
      CurrentTermEndDate__c = Date.today().addYears(1).addDays(-1),
      EstimateTitleName__c = '送付テスト見積',
      EstimateDate__c = Date.today(),
      EstimateValidDate__c = Date.today().addDays(30),
      EstimateSendContact__c = sendContact == null ? null : sendContact.Id,
      RenewEstimateAutoCreated__c = true
    );
    ContractTestDataFactory.applyRequiredFields(history);
    ContractTestDataFactory.applyEstimateOrderedOpportunity(history, account.Id);
    Boolean previousAllow = ContractHistoryTriggerHandler.allowRenewEstimateAutoCreatedWrite;
    ContractHistoryTriggerHandler.allowRenewEstimateAutoCreatedWrite = true;
    try {
      insert history;
    } finally {
      ContractHistoryTriggerHandler.allowRenewEstimateAutoCreatedWrite = previousAllow;
    }
    return history;
  }

  private static void insertLine(ContractHistory__c history) {
    ContractService__c service = [
      SELECT Account__c
      FROM ContractService__c
      WHERE Id = :history.ContractService__c
    ];
    Product2 product = ContractTestDataFactory.buildProduct(
      'Send Board Line ' + String.valueOf(Crypto.getRandomInteger())
    );
    product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
    ContractTestDataFactory.insertProduct(product);
    ContractProduct__c line = new ContractProduct__c(
      ContractHistory__c = history.Id,
      Account__c = service.Account__c,
      Product__c = product.Id,
      Quantity__c = 1,
      UnitPrice__c = 8000,
      Amount__c = 8000,
      StartDate__c = history.CurrentTermStartDate__c,
      Enddate__c = history.CurrentTermEndDate__c,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
      Type__c = 'New',
      RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_OVER_TIME
    );
    ContractTestDataFactory.applyRequiredFields(line);
    line.Amount__c = 8000;
    insert line;
  }

  private static String currentToken(Id historyId) {
    ContractHistory__c history = [
      SELECT LastModifiedDate
      FROM ContractHistory__c
      WHERE Id = :historyId
    ];
    return ContractOptimisticLockUtil.toToken(history.LastModifiedDate);
  }

  private static Id insertIssuedFile(Id linkedEntityId, String title) {
    ContentVersion version = new ContentVersion(
      Title = title,
      PathOnClient = title + '.pdf',
      VersionData = Blob.valueOf('issued'),
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
      LinkedEntityId = linkedEntityId,
      ShareType = 'V',
      Visibility = 'AllUsers'
    );
    return documentId;
  }

  @IsTest
  static void getBoardContext_rejectsWithout05() {
    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.SEND_ESTIMATE => false
    };
    Boolean thrown = false;
    try {
      EstimateSendBoardController.getBoardContext();
    } catch (AuraHandledException ex) {
      thrown = true;
    } finally {
      ContractPermissionUtil.testOverrides = null;
    }
    System.assertEquals(true, thrown, '共通基盤 第1.4節: 送付画面の読込は 05');
  }
}
