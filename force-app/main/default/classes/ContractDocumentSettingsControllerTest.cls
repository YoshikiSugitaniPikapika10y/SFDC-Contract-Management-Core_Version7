@IsTest
private class ContractDocumentSettingsControllerTest {
  @TestSetup
  static void setupPermission() {
    ContractPermissionUtil.testAllowAll = true;
    ContractPermissionUtil.testOverrides = null;
  }

  private static ContractDocumentSettingsController.CatalogLinkDto findLink(
    List<ContractDocumentSettingsController.CatalogLinkDto> rows,
    String key
  ) {
    for (ContractDocumentSettingsController.CatalogLinkDto row : rows) {
      if (row.key == key) {
        return row;
      }
    }
    return null;
  }

  /** 仕様: Core 第11.6節。開いたときの版と操作キーを付けて保存する。 */
  private static ContractDocumentSettingsController.SettingsDto saveWithFreshTokens(
    ContractDocumentSettingsController.SettingsDto input
  ) {
    ContractDocumentSettingsController.SettingsDto current =
      ContractDocumentSettingsController.getSettings().settings;
    input.documentSettingToken = current.documentSettingToken;
    input.accountingPolicyToken = current.accountingPolicyToken;
    input.validationEnforceToken = current.validationEnforceToken;
    input.lockExemptToken = current.lockExemptToken;
    input.paymentLockExemptToken = current.paymentLockExemptToken;
    input.journalLockExemptToken = current.journalLockExemptToken;
    input.amountCalculationToken = current.amountCalculationToken;
    input.businessOperationKey = AccountingCauseLockService.issueOperationKey();
    return ContractDocumentSettingsController.saveSettings(input);
  }

  @IsTest
  static void getSettingsReturnsOrganizationDefaultAndCandidates() {
    insert new ContractDocumentSetting__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      CompanyName__c = 'テスト株式会社',
      Address__c = '東京都',
      InvoiceRegistrationNumber__c = 'T1234567890123',
      BankTransferInfo__c = 'テスト銀行',
      EstimateSendMode__c = 'PdfOnly',
      InvoiceSendMode__c = 'PdfOnly'
    );

    Test.startTest();
    ContractDocumentSettingsController.testHasAccountingMaster = false;
    ContractDocumentSettingsController.PageDataDto result =
      ContractDocumentSettingsController.getSettings();
    Test.stopTest();

    System.assertEquals('テスト株式会社', result.settings.companyName);
    System.assertEquals('PdfOnly', result.settings.estimateSendMode);
    System.assertEquals('DOWN', result.settings.taxRoundingMode);
    System.assertEquals(
      'Scale2HalfUp',
      result.settings.quantityUnitPriceRoundingMode
    );
    System.assertEquals('Scale0HalfUp', result.settings.amountRoundingMode);
    System.assertEquals(
      'SignedLargestRemainder',
      result.settings.taxLineAllocationMethod
    );
    System.assertEquals(false, result.settings.validationEnforce);
    System.assertEquals(null, result.settings.lockExemptFieldApiNames);
    System.assertEquals(
      null,
      result.settings.policyFrozen,
      'Core 第1.1.10節: 会計方針0件はOFFと埋めない'
    );
    System.assertEquals(
      null,
      result.settings.accountingEnabled,
      'Core 第1.1.10節: 会計方針0件はOFFと埋めない'
    );
    System.assertEquals(null, result.settings.revenueRecognitionBasis);
    System.assertNotEquals(null, result.orgWideEmailAddresses);
    System.assertNotEquals(null, result.settingLinks);
    System.assertEquals(false, result.hasAccountingMaster);
    System.assertEquals(
      null,
      findLink(result.settingLinks, 'glAccounts'),
      'Core 第11.6節: 21が無ければ会計マスタのリンクを返さない'
    );
    System.assertNotEquals(
      null,
      findLink(result.settingLinks, 'documentCatalog')
    );
    System.assertEquals(
      '/lightning/setup/PermSets/home',
      findLink(result.settingLinks, 'permissionSets').url
    );
    ContractDocumentSettingsController.testHasAccountingMaster = null;
  }

  @IsTest
  static void saveSettingsCreatesAndUpdatesOrganizationDefault() {
    ContractDocumentSettingsController.SettingsDto input =
      new ContractDocumentSettingsController.SettingsDto();
    input.estimateSendMode = 'PdfOnly';
    input.invoiceSendMode = 'PdfOnly';
    input.companyName = ' 株式会社サンプル ';
    input.address = '東京都';
    input.invoiceRegistrationNumber = 'T1234567890123';
    input.bankTransferInfo = 'サンプル銀行 本店';
    input.documentFooter = 'ありがとうございました。';
    input.privacyPolicyUrl = 'https://example.com/privacy';
    input.estimateValidMonths = 1;
    input.defaultMonthlyCycles = 12;
    input.renewOpportunityEnabled = false;

    Test.startTest();
    ContractDocumentSettingsController.SettingsDto saved =
      saveWithFreshTokens(input);
    input.companyName = '更新後株式会社';
    saveWithFreshTokens(input);
    Test.stopTest();

    System.assertEquals('株式会社サンプル', saved.companyName);
    ContractDocumentSetting__c stored = [
      SELECT CompanyName__c, EstimateSendMode__c, InvoiceSendMode__c
      FROM ContractDocumentSetting__c
      WHERE SetupOwnerId = :UserInfo.getOrganizationId()
    ];
    System.assertEquals('更新後株式会社', stored.CompanyName__c);
    System.assertEquals('PdfOnly', stored.EstimateSendMode__c);
    System.assertEquals('PdfOnly', stored.InvoiceSendMode__c);
  }

  @IsTest
  static void saveSettings_deletesNonOrgHierarchyRows() {
    Id organizationId = UserInfo.getOrganizationId();
    Id userId = UserInfo.getUserId();
    insert new ContractDocumentSetting__c(
      SetupOwnerId = userId,
      CompanyName__c = 'ユーザー行'
    );
    insert new ContractValidationEnforce__c(
      SetupOwnerId = userId,
      Enforce__c = true
    );
    insert new InvoiceLockExemptFields__c(
      SetupOwnerId = userId,
      FieldApiNames__c = 'Memo__c'
    );
    insert new InvoicePaymentLockExemptFields__c(
      SetupOwnerId = userId,
      FieldApiNames__c = 'Memo__c'
    );
    insert new GlJournalLockExemptFields__c(
      SetupOwnerId = userId,
      FieldApiNames__c = 'Memo__c'
    );

    ContractDocumentSettingsController.SettingsDto input =
      new ContractDocumentSettingsController.SettingsDto();
    input.estimateSendMode = 'PdfOnly';
    input.invoiceSendMode = 'PdfOnly';
    input.companyName = '組織既定';
    input.address = '東京都';
    input.invoiceRegistrationNumber = 'T1234567890123';
    input.bankTransferInfo = '銀行';
    input.estimateValidMonths = 1;
    input.defaultMonthlyCycles = 12;
    input.lockExemptFieldApiNames = 'Memo__c';
    input.paymentLockExemptFieldApiNames = 'Memo__c';
    input.journalLockExemptFieldApiNames = 'Memo__c';
    input.validationEnforce = false;

    Test.startTest();
    saveWithFreshTokens(input);
    Test.stopTest();

    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM ContractDocumentSetting__c
        WHERE SetupOwnerId != :organizationId
      ],
      'Core 第11.6節: ユーザー単位の階層切替は持たない'
    );
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM ContractValidationEnforce__c
        WHERE SetupOwnerId != :organizationId
      ],
      'Core 第11.6節: カスタム入力規則をONは組織既定だけ'
    );
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM InvoiceLockExemptFields__c
        WHERE SetupOwnerId != :organizationId
      ],
      'Core 第11.6節: 請求ロック除外は組織既定だけ'
    );
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM InvoicePaymentLockExemptFields__c
        WHERE SetupOwnerId != :organizationId
      ],
      'Core 第11.6節: 入出金ロック除外は組織既定だけ'
    );
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM GlJournalLockExemptFields__c
        WHERE SetupOwnerId != :organizationId
      ],
      'Core 第11.6節: 仕訳ロック除外は組織既定だけ'
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM ContractDocumentSetting__c
        WHERE SetupOwnerId = :organizationId
      ],
      'Core 第11.6節: 組織既定は残す'
    );
  }

  @IsTest
  static void saveSettings_sameKeyRetry_appliesOnce() {
    ContractDocumentSettingsController.SettingsDto input =
      new ContractDocumentSettingsController.SettingsDto();
    input.estimateSendMode = 'PdfOnly';
    input.invoiceSendMode = 'PdfOnly';
    input.companyName = '初回会社';
    input.address = '東京都';
    input.invoiceRegistrationNumber = 'T1234567890123';
    input.bankTransferInfo = '銀行';
    input.estimateValidMonths = 1;
    input.defaultMonthlyCycles = 12;

    Test.startTest();
    ContractDocumentSettingsController.SettingsDto current =
      ContractDocumentSettingsController.getSettings().settings;
    input.documentSettingToken = current.documentSettingToken;
    input.accountingPolicyToken = current.accountingPolicyToken;
    input.validationEnforceToken = current.validationEnforceToken;
    input.lockExemptToken = current.lockExemptToken;
    input.amountCalculationToken = current.amountCalculationToken;
    input.businessOperationKey = 'org-settings-retry-key';
    ContractDocumentSettingsController.saveSettings(input);

    input.companyName = '再試行では載せない';
    current = ContractDocumentSettingsController.getSettings().settings;
    input.documentSettingToken = current.documentSettingToken;
    input.accountingPolicyToken = current.accountingPolicyToken;
    input.validationEnforceToken = current.validationEnforceToken;
    input.lockExemptToken = current.lockExemptToken;
    input.amountCalculationToken = current.amountCalculationToken;
    input.businessOperationKey = 'org-settings-retry-key';
    ContractDocumentSettingsController.SettingsDto retry =
      ContractDocumentSettingsController.saveSettings(input);
    Test.stopTest();

    System.assertEquals('初回会社', retry.companyName);
    ContractDocumentSetting__c stored = [
      SELECT CompanyName__c, BusinessOperationKey__c
      FROM ContractDocumentSetting__c
      WHERE SetupOwnerId = :UserInfo.getOrganizationId()
    ];
    System.assertEquals('初回会社', stored.CompanyName__c);
    System.assertEquals('org-settings-retry-key', stored.BusinessOperationKey__c);
  }

  @IsTest
  static void saveSettings_staleDocumentSettingToken_throws() {
    insert new ContractDocumentSetting__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      CompanyName__c = '既存',
      Address__c = '東京都',
      InvoiceRegistrationNumber__c = 'T1234567890123',
      BankTransferInfo__c = '銀行',
      EstimateSendMode__c = 'PdfOnly',
      InvoiceSendMode__c = 'PdfOnly',
      EstimateValidMonths__c = 1,
      DefaultMonthlyCycles__c = 12
    );
    ContractDocumentSettingsController.SettingsDto input =
      ContractDocumentSettingsController.getSettings().settings;
    input.companyName = '競合';
    input.documentSettingToken = '1';
    input.businessOperationKey = AccountingCauseLockService.issueOperationKey();

    Boolean thrown = false;
    Test.startTest();
    try {
      ContractDocumentSettingsController.saveSettings(input);
    } catch (AuraHandledException ex) {
      thrown = true;
      System.assert(
        ex.getMessage().contains('開き直'),
        'Core 第11.6節: 版不一致は画面を読み直す。実際: ' + ex.getMessage()
      );
    }
    Test.stopTest();
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void saveSettingsWritesContractHeadingFields() {
    ContractDocumentSettingsController.SettingsDto input =
      new ContractDocumentSettingsController.SettingsDto();
    input.estimateSendMode = 'PdfOnly';
    input.invoiceSendMode = 'PdfOnly';
    input.companyName = 'テスト発行会社';
    input.address = 'テスト住所';
    input.invoiceRegistrationNumber = 'T0000000000000';
    input.bankTransferInfo = 'テスト振込先';
    input.estimateValidMonths = 3;
    input.defaultMonthlyCycles = 24;
    input.renewOpportunityEnabled = true;

    Test.startTest();
    ContractDocumentSettingsController.SettingsDto saved =
      saveWithFreshTokens(input);
    Test.stopTest();

    System.assertEquals(3, saved.estimateValidMonths);
    System.assertEquals(24, saved.defaultMonthlyCycles);
    System.assertEquals(true, saved.renewOpportunityEnabled);
    ContractDocumentSetting__c stored = [
      SELECT
        EstimateValidMonths__c,
        DefaultMonthlyCycles__c,
        RenewOpportunityEnabled__c
      FROM ContractDocumentSetting__c
      WHERE SetupOwnerId = :UserInfo.getOrganizationId()
    ];
    System.assertEquals(
      3,
      stored.EstimateValidMonths__c,
      'Core 第11.6節: 見積有効期間を組織設定へ保存する'
    );
    System.assertEquals(
      24,
      stored.DefaultMonthlyCycles__c,
      '日付仕様 第2.5節: 既定サイクル数を組織設定へ保存する'
    );
    System.assertEquals(
      true,
      stored.RenewOpportunityEnabled__c,
      'Core 第11.5節: 更新商談スイッチを組織設定へ保存する'
    );
  }

  @IsTest
  static void saveSettingsRejectsOutOfRangeContractValues() {
    ContractDocumentSettingsController.SettingsDto input =
      new ContractDocumentSettingsController.SettingsDto();
    input.estimateSendMode = 'PdfOnly';
    input.invoiceSendMode = 'PdfOnly';
    input.estimateValidMonths = 0;
    input.defaultMonthlyCycles = 12;

    Boolean monthsThrown = false;
    try {
      saveWithFreshTokens(input);
    } catch (AuraHandledException ex) {
      monthsThrown = true;
      System.assert(
        ex.getMessage()
          .contains(
            ContractDocumentSettingService.INVALID_ESTIMATE_VALID_MONTHS_MESSAGE
          ),
        'Core 第4.10節: 範囲外の見積有効期間は1へ落とさず拒否する。実際: ' +
          ex.getMessage()
      );
    }
    System.assertEquals(true, monthsThrown);

    input.estimateValidMonths = 1;
    input.defaultMonthlyCycles = 37;
    Boolean cyclesThrown = false;
    try {
      saveWithFreshTokens(input);
    } catch (AuraHandledException ex) {
      cyclesThrown = true;
      System.assert(
        ex.getMessage()
          .contains(
            ContractDocumentSettingService.INVALID_DEFAULT_CYCLES_MESSAGE
          ),
        '日付仕様 第2.5節: 範囲外の既定サイクル数は12へ落とさず拒否する。実際: ' +
          ex.getMessage()
      );
    }
    System.assertEquals(true, cyclesThrown);
  }

  @IsTest
  static void saveSettings_pdfOnlySucceedsWithoutDefaultDocumentKeys() {
    ContractDocumentSettingsController.SettingsDto input =
      new ContractDocumentSettingsController.SettingsDto();
    applyPdfOnlyRequired(input);

    Test.startTest();
    ContractDocumentSettingsController.SettingsDto saved =
      saveWithFreshTokens(input);
    Test.stopTest();

    System.assertEquals(
      'PdfOnly',
      saved.estimateSendMode,
      'Core 第11.6節: 既定キー必須では保存を止めない'
    );
  }

  @IsTest
  static void saveAllowsPdfAndEmailWithoutCatalog() {
    ContractDocumentSettingsController.SettingsDto input =
      new ContractDocumentSettingsController.SettingsDto();
    applyPdfOnlyRequired(input);
    input.estimateSendMode = 'PdfAndEmail';
    input.estimateOrgWideEmailAddress = null;
    ContractEmailTemplateService.testRecords =
      new List<ContractEmailTemplate__mdt>();

    Test.startTest();
    ContractDocumentSettingsController.SettingsDto saved =
      saveWithFreshTokens(input);
    Test.stopTest();

    System.assertEquals(
      'PdfAndEmail',
      saved.estimateSendMode,
      'Core 第11.3.2節・第11.6節: 3択はカタログの状態に関係なく保存できる'
    );
  }

  @IsTest
  static void saveRejectsMissingVerifiedOrgSender() {
    ContractDocumentSettingsController.SettingsDto input =
      new ContractDocumentSettingsController.SettingsDto();
    applyPdfOnlyRequired(input);
    input.estimateSendMode = 'PdfAndEmail';
    input.estimateOrgWideEmailAddress = 'nosuch-sender@example.com';

    Boolean thrown = false;
    Test.startTest();
    try {
      saveWithFreshTokens(input);
    } catch (AuraHandledException ex) {
      thrown = true;
      System.assert(
        ex.getMessage()
          .contains(ContractDocumentSettingService.ORG_SENDER_NOT_FOUND_MESSAGE),
        'Core 第11.3.2節: 検証済み組織ワイドメール0件は保存エラー。実際: ' +
          ex.getMessage()
      );
    }
    Test.stopTest();
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void saveAllowsEstimatePdfAndEmailWithoutOrgSender() {
    ContractDocumentSettingsController.SettingsDto input =
      new ContractDocumentSettingsController.SettingsDto();
    applyPdfOnlyRequired(input);
    input.estimateSendMode = 'PdfAndEmail';
    input.estimateOrgWideEmailAddress = null;

    Test.startTest();
    ContractDocumentSettingsController.SettingsDto saved =
      saveWithFreshTokens(input);
    Test.stopTest();

    System.assertEquals(
      'PdfAndEmail',
      saved.estimateSendMode,
      'Core 第11.3.2節: PDFとメール送付でも見積用組織送信元は空でよい'
    );
    System.assertEquals(
      null,
      saved.estimateOrgWideEmailAddress
    );
  }

  @IsTest
  static void saveRejectsPdfOnlyWithoutCompanyName() {
    ContractDocumentSettingsController.SettingsDto input =
      new ContractDocumentSettingsController.SettingsDto();
    applyPdfOnlyRequired(input);
    input.companyName = null;

    Boolean thrown = false;
    Test.startTest();
    try {
      saveWithFreshTokens(input);
    } catch (AuraHandledException ex) {
      thrown = true;
      System.assert(
        ex.getMessage()
          .contains(ContractDocumentSettingService.MISSING_COMPANY_NAME_MESSAGE),
        'Core 第11.3.1節: 必須の空欄は保存でも止める。実際: ' + ex.getMessage()
      );
    }
    Test.stopTest();
    System.assertEquals(true, thrown);
  }

  private static void applyPdfOnlyRequired(
    ContractDocumentSettingsController.SettingsDto input
  ) {
    input.estimateSendMode = 'PdfOnly';
    input.invoiceSendMode = 'PdfOnly';
    input.companyName = 'テスト発行会社';
    input.address = 'テスト住所';
    input.invoiceRegistrationNumber = 'T0000000000000';
    input.bankTransferInfo = 'テスト振込先';
    input.estimateValidMonths = 1;
    input.defaultMonthlyCycles = 12;
  }

  @IsTest
  static void saveSettingsUpdatesAccountingPolicyWhenUnfrozen() {
    ContractDocumentSettingsController.SettingsDto input =
      new ContractDocumentSettingsController.SettingsDto();
    applyPdfOnlyRequired(input);
    input.accountingEnabled = true;
    input.revenueRecognitionBasis = 'CashBasis';
    input.taxRecognitionTiming = 'AtRecognition';
    input.monthlyBucketMethod = 'CalendarMonth';
    input.monthlyRecognitionDatePosition = 'MonthEnd';
    input.roundingTargetBucket = 'First';
    input.estimateValidMonths = 1;
    input.defaultMonthlyCycles = 12;

    Test.startTest();
    ContractDocumentSettingsController.SettingsDto saved =
      saveWithFreshTokens(input);
    Test.stopTest();

    System.assertEquals(true, saved.accountingEnabled);
    System.assertEquals('CashBasis', saved.revenueRecognitionBasis);
    System.assertEquals(false, saved.policyFrozen);
    GlAccountingPolicy__c policy = [
      SELECT
        AccountingEnabled__c,
        RevenueRecognitionBasis__c,
        TaxRecognitionTiming__c,
        MonthlyBucketMethod__c,
        MonthlyRecognitionDatePosition__c,
        RoundingTargetBucket__c,
        FrozenAt__c
      FROM GlAccountingPolicy__c
    ];
    System.assertEquals(true, policy.AccountingEnabled__c);
    System.assertEquals('CashBasis', policy.RevenueRecognitionBasis__c);
    System.assertEquals('AtRecognition', policy.TaxRecognitionTiming__c);
    System.assertEquals('CalendarMonth', policy.MonthlyBucketMethod__c);
    System.assertEquals('MonthEnd', policy.MonthlyRecognitionDatePosition__c);
    System.assertEquals('First', policy.RoundingTargetBucket__c);
    System.assertEquals(null, policy.FrozenAt__c);
  }

  @IsTest
  static void saveSettingsLeavesPolicyUnchangedAfterFreeze() {
    insert GlAccountingPolicyService.newOrgDefault();
    GlAccountingPolicyService.freezeOnFirstConfirm();
    ContractDocumentSettingsController.SettingsDto input =
      new ContractDocumentSettingsController.SettingsDto();
    applyPdfOnlyRequired(input);
    input.companyName = '固定後も帳票は保存';
    input.estimateValidMonths = 1;
    input.defaultMonthlyCycles = 12;
    input.accountingEnabled = true;
    input.revenueRecognitionBasis = 'CashBasis';

    Test.startTest();
    ContractDocumentSettingsController.SettingsDto saved =
      saveWithFreshTokens(input);
    Test.stopTest();

    System.assertEquals('固定後も帳票は保存', saved.companyName);
    System.assertEquals(true, saved.policyFrozen);
    System.assertEquals(false, saved.accountingEnabled);
    System.assertEquals('BillingBasis', saved.revenueRecognitionBasis);
    System.assertNotEquals(null, saved.frozenAtLabel);
    System.assertNotEquals(null, saved.frozenByName);
  }

  @IsTest
  static void saveSettingsAcceptsTaxRoundingModeAndRejectsUnknown() {
    ContractDocumentSettingsController.SettingsDto input =
      new ContractDocumentSettingsController.SettingsDto();
    applyPdfOnlyRequired(input);
    input.taxRoundingMode = 'UP';

    Test.startTest();
    ContractDocumentSettingsController.SettingsDto saved =
      saveWithFreshTokens(input);
    Test.stopTest();

    System.assertEquals(
      'UP',
      saved.taxRoundingMode,
      'Core 第11.9節: 税額丸めの変更を組織設定へ保存する'
    );
    System.assertEquals(
      'Scale2HalfUp',
      saved.quantityUnitPriceRoundingMode,
      'Core 第11.9節: 未指定の金額計算項目は OrgDefault のままにする'
    );

    input.taxRoundingMode = 'CEILING';
    Boolean thrown = false;
    try {
      saveWithFreshTokens(input);
    } catch (AuraHandledException ex) {
      thrown = true;
      System.assert(
        ex.getMessage().contains('税額丸め'),
        'Core 第1.1.10節: 未知の税額丸めは四捨五入へ落とさず拒否する。実際: ' +
          ex.getMessage()
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void saveSettingsWritesInputAndSystemHeadings() {
    ContractDocumentSettingsController.SettingsDto input =
      new ContractDocumentSettingsController.SettingsDto();
    applyPdfOnlyRequired(input);
    input.validationEnforce = true;
    input.lockExemptFieldApiNames = 'Memo__c,SentDate__c';
    input.paymentLockExemptFieldApiNames = 'Memo__c';
    input.journalLockExemptFieldApiNames = 'Memo__c';

    Test.startTest();
    ContractDocumentSettingsController.SettingsDto saved =
      saveWithFreshTokens(input);
    Test.stopTest();

    System.assertEquals(
      true,
      saved.validationEnforce,
      'Core 第11.6節: 顧客固有Validation Ruleの強制を組織設定へ保存する'
    );
    System.assertEquals(
      'Memo__c,SentDate__c',
      saved.lockExemptFieldApiNames,
      'Core 第11.6節: 請求ロック除外をシードへ落とさず入力値のまま保存する'
    );
    ContractValidationEnforce__c enforce =
      ContractValidationEnforce__c.getOrgDefaults();
    System.assertEquals(true, enforce.Enforce__c);
    InvoiceLockExemptFields__c lockExempt =
      InvoiceLockExemptFields__c.getOrgDefaults();
    System.assertEquals('Memo__c,SentDate__c', lockExempt.FieldApiNames__c);
    System.assertEquals(
      false,
      lockExempt.FieldApiNames__c.contains('InvoiceTransactionStatus__c'),
      'Core 第1.1.10節: ロック除外の空または部分入力をシード一覧へ埋めない'
    );
    System.assertEquals(
      'Memo__c',
      saved.paymentLockExemptFieldApiNames,
      'Core 第11.6節: 入出金ロック除外をシードへ落とさず入力値のまま保存する'
    );
    System.assertEquals(
      'Memo__c',
      saved.journalLockExemptFieldApiNames,
      'Core 第11.6節: 仕訳ロック除外をシードへ落とさず入力値のまま保存する'
    );
    InvoicePaymentLockExemptFields__c paymentLockExempt =
      InvoicePaymentLockExemptFields__c.getOrgDefaults();
    System.assertEquals('Memo__c', paymentLockExempt.FieldApiNames__c);
    GlJournalLockExemptFields__c journalLockExempt =
      GlJournalLockExemptFields__c.getOrgDefaults();
    System.assertEquals('Memo__c', journalLockExempt.FieldApiNames__c);
  }

  @IsTest
  static void saveStoresEstimateAndInvoiceOrgSendersSeparately() {
    ContractDocumentSettingsController.SettingsDto input =
      new ContractDocumentSettingsController.SettingsDto();
    applyPdfOnlyRequired(input);
    input.estimateSendMode = 'PdfAndEmail';
    input.invoiceSendMode = 'PdfAndEmail';
    String orgSender = ContractTestDataFactory.requireVerifiedOrgWideAddress();
    input.estimateOrgWideEmailAddress = orgSender;
    input.invoiceOrgWideEmailAddress = orgSender;

    Test.startTest();
    ContractDocumentSettingsController.SettingsDto saved =
      saveWithFreshTokens(input);
    Test.stopTest();

    System.assertEquals(
      orgSender,
      saved.estimateOrgWideEmailAddress,
      'Core 第11.3.2節: 見積用組織送信元は見積の項目へ保存する'
    );
    System.assertEquals(
      orgSender,
      saved.invoiceOrgWideEmailAddress,
      'Core 第11.3.2節: 請求用組織送信元は請求の項目へ保存する'
    );
  }

  @IsTest
  static void saveRejectsInvoicePdfAndEmailWhenOnlyEstimateSenderSet() {
    ContractDocumentSettingsController.SettingsDto input =
      new ContractDocumentSettingsController.SettingsDto();
    applyPdfOnlyRequired(input);
    input.invoiceSendMode = 'PdfAndEmail';
    input.estimateOrgWideEmailAddress = null;

    Boolean thrown = false;
    Test.startTest();
    try {
      saveWithFreshTokens(input);
    } catch (AuraHandledException ex) {
      thrown = true;
      System.assert(
        ex.getMessage()
          .contains(ContractDocumentSettingService.MISSING_ORG_SENDER_MESSAGE),
        'Core 第11.3.2節: 請求がPDFとメール送付なら請求用送信元は必須。実際: ' +
          ex.getMessage()
      );
    }
    Test.stopTest();
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void permissionIsRequired() {
    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.ORG_SETTINGS => false
    };

    Test.startTest();
    try {
      ContractDocumentSettingsController.getSettings();
      System.assert(false, '権限なしでは取得できないこと');
    } catch (AuraHandledException ex) {
      System.assert(ex.getMessage().contains('権限がありません'));
    }
    Test.stopTest();
  }

  @IsTest
  static void getSettings_includesAccountingMasterLinksWhenPermission21Assigned() {
    ContractDocumentSettingsController.testHasAccountingMaster = true;
    try {
      Test.startTest();
      ContractDocumentSettingsController.PageDataDto result =
        ContractDocumentSettingsController.getSettings();
      Test.stopTest();
      System.assertEquals(true, result.hasAccountingMaster);
      System.assertEquals(
        '/lightning/o/GlAccount__c/list',
        findLink(result.settingLinks, 'glAccounts').url
      );
      System.assertEquals(
        '/lightning/o/GlConditionSet__c/list',
        findLink(result.settingLinks, 'conditionSets').url
      );
      System.assertEquals(
        '/lightning/o/GlAccountMap__c/list',
        findLink(result.settingLinks, 'accountMaps').url
      );
      System.assertEquals(
        '/lightning/o/GlAccountingTagRule__c/list',
        findLink(result.settingLinks, 'tagRules').url
      );
      System.assertEquals(
        '/lightning/o/GlManualJournalSetting__c/list',
        findLink(result.settingLinks, 'manualJournals').url
      );
    } finally {
      ContractDocumentSettingsController.testHasAccountingMaster = null;
    }
  }

  @IsTest
  static void validateFieldCopyDefinitions_succeedsWhenDefinitionsAreValid() {
    Test.startTest();
    String message = ContractDocumentSettingsController.validateFieldCopyDefinitions();
    Test.stopTest();

    System.assertEquals(
      'コピー設定に不備はありません。',
      message,
      'Accounting 第3.1節: 設定画面からコピー設定を任意検証できる'
    );
  }

  @IsTest
  static void validateFieldCopyDefinitions_rejectsUnreachableRequiredJournalField() {
    FieldCopyDefinitionService.additionalRequiredJournalFieldApiNames = new Set<String>{
      'Memo__c'
    };
    Boolean rejected = false;
    try {
      Test.startTest();
      ContractDocumentSettingsController.validateFieldCopyDefinitions();
      Test.stopTest();
    } catch (AuraHandledException ex) {
      rejected = true;
      System.assert(
        ex.getMessage().contains('Memo__c'),
        'Accounting 第3.1節: 必須項目へ届かないコピー設定を設定画面の検証で出す。実際: ' +
          ex.getMessage()
      );
    } finally {
      FieldCopyDefinitionService.additionalRequiredJournalFieldApiNames = null;
    }
    System.assertEquals(true, rejected);
  }
}
