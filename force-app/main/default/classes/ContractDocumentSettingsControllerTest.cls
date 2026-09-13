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
    ContractDocumentSettingsController.SettingsDto current = ContractDocumentSettingsController.getSettings()
      .settings;
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
    ContractDocumentSettingsController.PageDataDto result = ContractDocumentSettingsController.getSettings();
    Test.stopTest();

    System.assertEquals('テスト株式会社', result.settings.companyName);
    System.assertEquals('東京都', result.settings.address);
    System.assertEquals(
      'T1234567890123',
      result.settings.invoiceRegistrationNumber
    );
    System.assertEquals('テスト銀行', result.settings.bankTransferInfo);
    System.assertEquals('PdfOnly', result.settings.estimateSendMode);
    System.assertEquals('PdfOnly', result.settings.invoiceSendMode);
    System.assertEquals(null, result.settings.documentFooter);
    System.assertEquals(null, result.settings.privacyPolicyUrl);
    System.assertEquals(false, result.settings.renewOpportunityEnabled);
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
    System.assertEquals(
      'InvoiceLineStableOrder',
      result.settings.allocationTieBreak
    );
    System.assertEquals(
      'EqualSplit',
      result.settings.monthlyBucketAmountMethod
    );
    System.assertEquals(
      'SignedRevenueRatio',
      result.settings.taxScheduleAllocationMethod
    );
    System.assertEquals(
      'OpenInclusiveRatio',
      result.settings.paymentLineAllocationMethod
    );
    System.assertEquals(
      'SameRate',
      result.settings.accountBalanceAllocationMethod
    );
    System.assertEquals(
      'ExclusiveRatioLastAbsorbs',
      result.settings.documentGroupTaxAllocationMethod,
      'Core 第11.9節: 金額計算はOrgDefaultの10項目を読み取る'
    );
    System.assertEquals(false, result.settings.validationEnforce);
    System.assertEquals(null, result.settings.lockExemptFieldApiNames);
    System.assertEquals(
      false,
      result.settings.policyFrozen,
      '仕様: Accounting 第3.1節。無いとき画面にシード値。固定ではない'
    );
    System.assertEquals(
      false,
      result.settings.accountingEnabled,
      '仕様: Accounting 第3.1節。無いとき画面にシード値'
    );
    System.assertEquals(
      'BillingBasis',
      result.settings.revenueRecognitionBasis,
      '仕様: Accounting 第3.1節。無いとき画面にシード値'
    );
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
  static void getSettings_whenNoRecords_returnsSeedsWithoutInsert() {
    Test.startTest();
    ContractDocumentSettingsController.PageDataDto result = ContractDocumentSettingsController.getSettings();
    Test.stopTest();

    System.assertEquals(
      'PdfOnly',
      result.settings.estimateSendMode,
      '仕様: Core 第11.6節。無いとき画面にシード値'
    );
    System.assertEquals('PdfOnly', result.settings.invoiceSendMode);
    System.assertEquals(12, result.settings.defaultMonthlyCycles);
    System.assertEquals(1, result.settings.estimateValidMonths);
    System.assertEquals(false, result.settings.renewOpportunityEnabled);
    System.assertEquals(false, result.settings.accountingEnabled);
    System.assertEquals('BillingBasis', result.settings.revenueRecognitionBasis);
    System.assertEquals('AtInvoice', result.settings.taxRecognitionTiming);
    System.assertEquals('Auto', result.settings.monthlyBucketMethod);
    System.assertEquals('BucketEnd', result.settings.monthlyRecognitionDatePosition);
    System.assertEquals('Last', result.settings.roundingTargetBucket);
    System.assertEquals(0, [SELECT COUNT() FROM ContractDocumentSetting__c]);
    System.assertEquals(0, [SELECT COUNT() FROM GlAccountingPolicy__c]);
  }

  @IsTest
  static void saveSettings_doesNotDuplicatePolicy() {
    ContractDocumentSettingsController.SettingsDto input = new ContractDocumentSettingsController.SettingsDto();
    input.estimateSendMode = 'PdfOnly';
    input.invoiceSendMode = 'PdfOnly';
    input.companyName = '初回';
    input.address = '東京都';
    input.invoiceRegistrationNumber = 'T1234567890123';
    input.bankTransferInfo = '銀行';
    input.estimateValidMonths = 1;
    input.defaultMonthlyCycles = 12;
    saveWithFreshTokens(input);
    Id firstPolicyId = [SELECT Id FROM GlAccountingPolicy__c].Id;

    input.companyName = '二回目';
    saveWithFreshTokens(input);

    System.assertEquals(
      1,
      [SELECT COUNT() FROM GlAccountingPolicy__c],
      'Accounting 第3.1節: 会計方針は組織内1件だけを維持する'
    );
    System.assertEquals(
      firstPolicyId,
      [SELECT Id FROM GlAccountingPolicy__c].Id,
      'Accounting 第3.1節: 組織設定の再保存で会計方針を作り直さない'
    );
    System.assertEquals(
      '二回目',
      [SELECT CompanyName__c FROM ContractDocumentSetting__c].CompanyName__c,
      'Core 第11.6節: 会計方針を増やさず帳票設定の再保存結果は反映する'
    );
  }

  @IsTest
  static void getSettings_cmdtLinksGoToSetupManageRecords() {
    Test.startTest();
    ContractDocumentSettingsController.testHasAccountingMaster = false;
    ContractDocumentSettingsController.PageDataDto result = ContractDocumentSettingsController.getSettings();
    Test.stopTest();

    System.assertEquals(
      cmdtManageRecordsUrl(ContractDocumentTemplate__mdt.SObjectType),
      findLink(result.settingLinks, 'documentCatalog').url,
      'Core 第11.3.2節: 帳票カタログは当該種別の行一覧'
    );
    System.assertEquals(
      cmdtManageRecordsUrl(ContractEmailTemplate__mdt.SObjectType),
      findLink(result.settingLinks, 'emailCatalog').url,
      'Core 第11.3.2節: 送付メールカタログは当該種別の行一覧'
    );
    System.assertEquals(
      cmdtManageRecordsUrl(EstimateWizardField__mdt.SObjectType),
      findLink(result.settingLinks, 'estimateWizardFields').url,
      'Core 第11.4.1節: 見積ウィザード追加項目は当該種別の行一覧'
    );
    System.assertEquals(
      cmdtManageRecordsUrl(OrderWizardField__mdt.SObjectType),
      findLink(result.settingLinks, 'orderWizardFields').url
    );
    System.assertEquals(
      cmdtManageRecordsUrl(InvoiceOpsField__mdt.SObjectType),
      findLink(result.settingLinks, 'invoiceOpsFields').url
    );
    System.assertEquals(
      cmdtManageRecordsUrl(GlAccountingSetting__mdt.SObjectType),
      findLink(result.settingLinks, 'amountCalculation').url
    );
    System.assertEquals(
      '/lightning/o/FieldCopyDefinition__c/list',
      findLink(result.settingLinks, 'fieldCopy').url,
      'Core 第11.6節: コピーはオブジェクト一覧のまま'
    );
    System.assert(
      !findLink(result.settingLinks, 'documentCatalog')
        .url.contains('CustomMetadata/home'),
      'Core 第11.3.2節: 種類の目次は使わない'
    );
    System.assert(
      !findLink(result.settingLinks, 'documentCatalog')
        .url.contains('/lightning/o/'),
      'Core 第11.6節: CMDT を LEX 一覧へ出さない'
    );
    ContractDocumentSettingsController.testHasAccountingMaster = null;
  }

  private static String cmdtManageRecordsUrl(Schema.SObjectType token) {
    return '/lightning/setup/CustomMetadata/page?address=%2F' +
      token.getDescribe().getKeyPrefix();
  }

  @IsTest
  static void saveSettingsCreatesAndUpdatesOrganizationDefault() {
    ContractDocumentSettingsController.SettingsDto input = new ContractDocumentSettingsController.SettingsDto();
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
    ContractDocumentSettingsController.SettingsDto saved = saveWithFreshTokens(
      input
    );
    input.companyName = '更新後株式会社';
    saveWithFreshTokens(input);
    Test.stopTest();

    System.assertEquals('株式会社サンプル', saved.companyName);
    ContractDocumentSetting__c stored = [
      SELECT
        CompanyName__c,
        Address__c,
        InvoiceRegistrationNumber__c,
        BankTransferInfo__c,
        DocumentFooter__c,
        PrivacyPolicyUrl__c,
        EstimateSendMode__c,
        InvoiceSendMode__c,
        EstimateValidMonths__c,
        DefaultMonthlyCycles__c,
        RenewOpportunityEnabled__c
      FROM ContractDocumentSetting__c
      WHERE SetupOwnerId = :UserInfo.getOrganizationId()
    ];
    System.assertEquals('更新後株式会社', stored.CompanyName__c);
    System.assertEquals('東京都', stored.Address__c);
    System.assertEquals('T1234567890123', stored.InvoiceRegistrationNumber__c);
    System.assertEquals('サンプル銀行 本店', stored.BankTransferInfo__c);
    System.assertEquals('ありがとうございました。', stored.DocumentFooter__c);
    System.assertEquals(
      'https://example.com/privacy',
      stored.PrivacyPolicyUrl__c
    );
    System.assertEquals('PdfOnly', stored.EstimateSendMode__c);
    System.assertEquals('PdfOnly', stored.InvoiceSendMode__c);
    System.assertEquals(1, stored.EstimateValidMonths__c);
    System.assertEquals(12, stored.DefaultMonthlyCycles__c);
    System.assertEquals(false, stored.RenewOpportunityEnabled__c);
    System.assertEquals(
      1,
      [SELECT COUNT() FROM GlAccountingPolicy__c],
      '仕様: Accounting 第3.1節。初回保存で方針1件を既定値で書く'
    );
    GlAccountingPolicy__c firstPolicy = [
      SELECT
        AccountingEnabled__c,
        RevenueRecognitionBasis__c,
        TaxRecognitionTiming__c,
        MonthlyBucketMethod__c,
        MonthlyRecognitionDatePosition__c,
        RoundingTargetBucket__c
      FROM GlAccountingPolicy__c
    ];
    System.assertEquals(false, firstPolicy.AccountingEnabled__c);
    System.assertEquals('BillingBasis', firstPolicy.RevenueRecognitionBasis__c);
    System.assertEquals('AtInvoice', firstPolicy.TaxRecognitionTiming__c);
    System.assertEquals('Auto', firstPolicy.MonthlyBucketMethod__c);
    System.assertEquals('BucketEnd', firstPolicy.MonthlyRecognitionDatePosition__c);
    System.assertEquals('Last', firstPolicy.RoundingTargetBucket__c);
    System.assertEquals(
      0,
      [SELECT COUNT() FROM FieldCopyDefinition__c],
      '仕様: Core 第11.4.2節。コピー見本は自動では入れない'
    );
    System.assertEquals(
      0,
      [SELECT COUNT() FROM GlAccount__c],
      '仕様: Accounting 第4.1節。科目は自動では入れない'
    );
    System.assertEquals(
      0,
      [SELECT COUNT() FROM GlManualJournalSetting__c],
      '仕様: Accounting 第10.2節。手動仕訳は自動では入れない'
    );
    System.assertEquals(
      0,
      [SELECT COUNT() FROM InvoiceLockExemptFields__c],
      '仕様: Core 第11.6節。ロック除外は保存でも作らない'
    );
    System.assertEquals(
      0,
      [SELECT COUNT() FROM InvoicePaymentLockExemptFields__c],
      '仕様: Core 第11.6節。ロック除外は保存でも作らない'
    );
    System.assertEquals(
      0,
      [SELECT COUNT() FROM GlJournalLockExemptFields__c],
      '仕様: Core 第11.6節。ロック除外は保存でも作らない'
    );

    ContractDocumentSettingsController.SettingsDto readback = ContractDocumentSettingsController.getSettings()
      .settings;
    System.assertEquals('更新後株式会社', readback.companyName);
    System.assertEquals('ありがとうございました。', readback.documentFooter);
    System.assertEquals(
      'https://example.com/privacy',
      readback.privacyPolicyUrl
    );
  }

  @IsTest
  static void saveSettings_secondSaveUsesReturnedTokens() {
    ContractDocumentSettingsController.SettingsDto input = new ContractDocumentSettingsController.SettingsDto();
    input.estimateSendMode = 'PdfOnly';
    input.invoiceSendMode = 'PdfOnly';
    input.companyName = '連続保存1';
    input.address = '東京都';
    input.invoiceRegistrationNumber = 'T1234567890123';
    input.bankTransferInfo = '銀行';
    input.estimateValidMonths = 1;
    input.defaultMonthlyCycles = 12;

    ContractDocumentSettingsController.SettingsDto first = saveWithFreshTokens(
      input
    );
    input.companyName = '連続保存2';
    input.documentSettingToken = first.documentSettingToken;
    input.accountingPolicyToken = first.accountingPolicyToken;
    input.validationEnforceToken = first.validationEnforceToken;
    input.lockExemptToken = first.lockExemptToken;
    input.paymentLockExemptToken = first.paymentLockExemptToken;
    input.journalLockExemptToken = first.journalLockExemptToken;
    input.amountCalculationToken = first.amountCalculationToken;
    input.businessOperationKey = AccountingCauseLockService.issueOperationKey();

    Test.startTest();
    ContractDocumentSettingsController.SettingsDto second = ContractDocumentSettingsController.saveSettings(
      input
    );
    Test.stopTest();

    System.assertEquals('連続保存2', second.companyName);
    ContractDocumentSetting__c stored = [
      SELECT CompanyName__c
      FROM ContractDocumentSetting__c
      WHERE SetupOwnerId = :UserInfo.getOrganizationId()
    ];
    System.assertEquals('連続保存2', stored.CompanyName__c);
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

    ContractDocumentSettingsController.SettingsDto input = new ContractDocumentSettingsController.SettingsDto();
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
    ContractDocumentSettingsController.SettingsDto input = new ContractDocumentSettingsController.SettingsDto();
    input.estimateSendMode = 'PdfOnly';
    input.invoiceSendMode = 'PdfOnly';
    input.companyName = '初回会社';
    input.address = '東京都';
    input.invoiceRegistrationNumber = 'T1234567890123';
    input.bankTransferInfo = '銀行';
    input.estimateValidMonths = 1;
    input.defaultMonthlyCycles = 12;

    Test.startTest();
    ContractDocumentSettingsController.SettingsDto current = ContractDocumentSettingsController.getSettings()
      .settings;
    input.documentSettingToken = current.documentSettingToken;
    input.accountingPolicyToken = current.accountingPolicyToken;
    input.validationEnforceToken = current.validationEnforceToken;
    input.lockExemptToken = current.lockExemptToken;
    input.paymentLockExemptToken = current.paymentLockExemptToken;
    input.journalLockExemptToken = current.journalLockExemptToken;
    input.amountCalculationToken = current.amountCalculationToken;
    input.businessOperationKey = 'org-settings-retry-key';
    ContractDocumentSettingsController.saveSettings(input);

    input.companyName = '再試行では載せない';
    current = ContractDocumentSettingsController.getSettings().settings;
    input.documentSettingToken = current.documentSettingToken;
    input.accountingPolicyToken = current.accountingPolicyToken;
    input.validationEnforceToken = current.validationEnforceToken;
    input.lockExemptToken = current.lockExemptToken;
    input.paymentLockExemptToken = current.paymentLockExemptToken;
    input.journalLockExemptToken = current.journalLockExemptToken;
    input.amountCalculationToken = current.amountCalculationToken;
    input.businessOperationKey = 'org-settings-retry-key';
    ContractDocumentSettingsController.SettingsDto retry = ContractDocumentSettingsController.saveSettings(
      input
    );
    Test.stopTest();

    System.assertEquals('初回会社', retry.companyName);
    ContractDocumentSetting__c stored = [
      SELECT CompanyName__c, BusinessOperationKey__c
      FROM ContractDocumentSetting__c
      WHERE SetupOwnerId = :UserInfo.getOrganizationId()
    ];
    System.assertEquals('初回会社', stored.CompanyName__c);
    System.assertEquals(
      'org-settings-retry-key',
      stored.BusinessOperationKey__c
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM ContractOperationLog__c
        WHERE BusinessOperationKey__c = 'org-settings-retry-key'
      ],
      'Core 第11.6節・第4.3.12節: 同じ業務操作キーの再試行は1件の保存のまま'
    );
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
    ContractDocumentSettingsController.SettingsDto input = ContractDocumentSettingsController.getSettings()
      .settings;
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
    ContractDocumentSetting__c storedAfterConflict = [
      SELECT CompanyName__c
      FROM ContractDocumentSetting__c
      WHERE SetupOwnerId = :UserInfo.getOrganizationId()
    ];
    System.assertEquals(
      '既存',
      storedAfterConflict.CompanyName__c,
      'Core 第4.3.12節: 版不一致は先に保存された内容を上書きしない'
    );
  }

  @IsTest
  static void saveSettingsWritesContractHeadingFields() {
    ContractDocumentSettingsController.SettingsDto input = new ContractDocumentSettingsController.SettingsDto();
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
    ContractDocumentSettingsController.SettingsDto saved = saveWithFreshTokens(
      input
    );
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
    ContractDocumentSettingsController.SettingsDto readback = ContractDocumentSettingsController.getSettings()
      .settings;
    System.assertEquals(3, readback.estimateValidMonths);
    System.assertEquals(24, readback.defaultMonthlyCycles);
    System.assertEquals(true, readback.renewOpportunityEnabled);
  }

  @IsTest
  static void saveSettingsRejectsOutOfRangeContractValues() {
    ContractDocumentSettingsController.SettingsDto input = new ContractDocumentSettingsController.SettingsDto();
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

    input.estimateValidMonths = 1.5;
    input.defaultMonthlyCycles = 12;
    Boolean fractionalMonthsThrown = false;
    try {
      saveWithFreshTokens(input);
    } catch (AuraHandledException ex) {
      fractionalMonthsThrown = true;
      System.assert(
        ex.getMessage()
          .contains(
            ContractDocumentSettingService.INVALID_ESTIMATE_VALID_MONTHS_MESSAGE
          ),
        '日付仕様 第2.6節: 小数の見積有効期間は拒否する。実際: ' +
        ex.getMessage()
      );
    }
    System.assertEquals(true, fractionalMonthsThrown);

    input.estimateValidMonths = 1;
    input.defaultMonthlyCycles = 12.5;
    Boolean fractionalCyclesThrown = false;
    try {
      saveWithFreshTokens(input);
    } catch (AuraHandledException ex) {
      fractionalCyclesThrown = true;
      System.assert(
        ex.getMessage()
          .contains(
            ContractDocumentSettingService.INVALID_DEFAULT_CYCLES_MESSAGE
          ),
        '日付仕様 第2.5節: 小数の既定サイクル数は拒否する。実際: ' +
        ex.getMessage()
      );
    }
    System.assertEquals(true, fractionalCyclesThrown);
  }

  @IsTest
  static void saveAllowsPdfAndEmailWithoutCatalog() {
    ContractDocumentSettingsController.SettingsDto input = new ContractDocumentSettingsController.SettingsDto();
    applyPdfOnlyRequired(input);
    input.estimateSendMode = 'PdfAndEmail';
    input.estimateOrgWideEmailAddress = null;
    ContractEmailTemplateService.testRecords = new List<ContractEmailTemplate__mdt>();

    Test.startTest();
    ContractDocumentSettingsController.SettingsDto saved = saveWithFreshTokens(
      input
    );
    Test.stopTest();

    System.assertEquals(
      'PdfAndEmail',
      saved.estimateSendMode,
      'Core 第11.3.2節・第11.6節: 3択はカタログの状態に関係なく保存できる'
    );
    System.assertEquals(
      'PdfAndEmail',
      ContractDocumentSettingsController.getSettings()
        .settings.estimateSendMode,
      'Core 第11.3.2節: カタログ0件でも選んだ3択を読み戻せる'
    );
  }

  @IsTest
  static void saveRejectsMissingVerifiedOrgSender() {
    ContractDocumentSettingsController.SettingsDto input = new ContractDocumentSettingsController.SettingsDto();
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
          .contains(
            ContractDocumentSettingService.ORG_SENDER_NOT_FOUND_MESSAGE
          ),
        'Core 第11.3.2節: 検証済み組織ワイドメール0件は保存エラー。実際: ' +
        ex.getMessage()
      );
    }
    Test.stopTest();
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void saveAllowsEstimatePdfAndEmailWithoutOrgSender() {
    ContractDocumentSettingsController.SettingsDto input = new ContractDocumentSettingsController.SettingsDto();
    applyPdfOnlyRequired(input);
    input.estimateSendMode = 'PdfAndEmail';
    input.estimateOrgWideEmailAddress = null;

    Test.startTest();
    ContractDocumentSettingsController.SettingsDto saved = saveWithFreshTokens(
      input
    );
    Test.stopTest();

    System.assertEquals(
      'PdfAndEmail',
      saved.estimateSendMode,
      'Core 第11.3.2節: PDFとメール送付でも見積用組織送信元は空でよい'
    );
    System.assertEquals(null, saved.estimateOrgWideEmailAddress);
  }

  @IsTest
  static void saveRejectsMissingRequiredCompanyInformation() {
    ContractDocumentSettingsController.SettingsDto input = new ContractDocumentSettingsController.SettingsDto();
    applyPdfOnlyRequired(input);
    input.companyName = null;

    Test.startTest();
    assertSaveRejected(
      input,
      ContractDocumentSettingService.MISSING_COMPANY_NAME_MESSAGE,
      'Core 第11.3.1節: 帳票を使うときは会社名が必須'
    );
    input.companyName = 'テスト発行会社';
    input.address = null;
    assertSaveRejected(
      input,
      ContractDocumentSettingService.MISSING_ADDRESS_MESSAGE,
      'Core 第11.3.1節: 帳票を使うときは住所が必須'
    );
    input.address = 'テスト住所';
    input.invoiceRegistrationNumber = null;
    assertSaveRejected(
      input,
      ContractDocumentSettingService.MISSING_REGISTRATION_NUMBER_MESSAGE,
      'Core 第11.3.1節: 請求書を使うときは登録番号が必須'
    );
    input.invoiceRegistrationNumber = 'T0000000000000';
    input.bankTransferInfo = null;
    assertSaveRejected(
      input,
      ContractDocumentSettingService.MISSING_BANK_TRANSFER_MESSAGE,
      'Core 第11.3.1節: 請求書を使うときは振込先が必須'
    );
    Test.stopTest();
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM ContractDocumentSetting__c
        WHERE SetupOwnerId = :UserInfo.getOrganizationId()
      ],
      'Core 第11.3.1節: 必須不足では組織設定を保存しない'
    );
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

  private static void assertSaveRejected(
    ContractDocumentSettingsController.SettingsDto input,
    String expectedMessage,
    String assertionMessage
  ) {
    Boolean thrown = false;
    try {
      saveWithFreshTokens(input);
    } catch (AuraHandledException ex) {
      thrown = true;
      System.assert(
        ex.getMessage().contains(expectedMessage),
        assertionMessage + '。実際: ' + ex.getMessage()
      );
    }
    System.assertEquals(true, thrown, assertionMessage);
  }

  @IsTest
  static void saveSettingsUpdatesAccountingPolicyWhenUnfrozen() {
    ContractDocumentSettingsController.SettingsDto input = new ContractDocumentSettingsController.SettingsDto();
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
    ContractDocumentSettingsController.SettingsDto saved = saveWithFreshTokens(
      input
    );
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
  static void saveSettingsPreservesFrozenPolicyWhileSavingDocumentSettings() {
    insert GlAccountingPolicyService.newOrgDefault();
    GlAccountingPolicyService.freezeOnFirstConfirm();
    ContractDocumentSettingsController.SettingsDto frozen = ContractDocumentSettingsController.getSettings()
      .settings;
    ContractDocumentSettingsController.SettingsDto input = new ContractDocumentSettingsController.SettingsDto();
    applyPdfOnlyRequired(input);
    input.companyName = '固定後も帳票は保存';
    input.estimateValidMonths = 1;
    input.defaultMonthlyCycles = 12;
    input.accountingEnabled = frozen.accountingEnabled;
    input.revenueRecognitionBasis = frozen.revenueRecognitionBasis;
    input.taxRecognitionTiming = frozen.taxRecognitionTiming;
    input.monthlyBucketMethod = frozen.monthlyBucketMethod;
    input.monthlyRecognitionDatePosition = frozen.monthlyRecognitionDatePosition;
    input.roundingTargetBucket = frozen.roundingTargetBucket;

    Test.startTest();
    ContractDocumentSettingsController.SettingsDto saved = saveWithFreshTokens(
      input
    );
    Test.stopTest();

    System.assertEquals('固定後も帳票は保存', saved.companyName);
    System.assertEquals(true, saved.policyFrozen);
    System.assertEquals(false, saved.accountingEnabled);
    System.assertEquals('BillingBasis', saved.revenueRecognitionBasis);
    System.assertNotEquals(null, saved.frozenAtLabel);
    System.assertNotEquals(null, saved.frozenByName);
    ContractDocumentSetting__c storedDocument = [
      SELECT CompanyName__c
      FROM ContractDocumentSetting__c
      WHERE SetupOwnerId = :UserInfo.getOrganizationId()
    ];
    System.assertEquals(
      '固定後も帳票は保存',
      storedDocument.CompanyName__c,
      'Core 第11.6節: 固定後も帳票設定は保存する'
    );
    GlAccountingPolicy__c storedPolicy = [
      SELECT AccountingEnabled__c, RevenueRecognitionBasis__c, FrozenAt__c
      FROM GlAccountingPolicy__c
    ];
    System.assertEquals(false, storedPolicy.AccountingEnabled__c);
    System.assertEquals(
      'BillingBasis',
      storedPolicy.RevenueRecognitionBasis__c
    );
    System.assertNotEquals(
      null,
      storedPolicy.FrozenAt__c,
      'Accounting 第3.1節: 固定後の会計方針を上書きしない'
    );
  }

  @IsTest
  static void saveSettingsResolvesAllowedAmountCalculationAndRejectsUnknown() {
    ContractDocumentSettingsController.SettingsDto input = new ContractDocumentSettingsController.SettingsDto();
    applyPdfOnlyRequired(input);
    input.taxRoundingMode = 'UP';

    Test.startTest();
    ContractDocumentSettingsController.SettingsDto saved = saveWithFreshTokens(
      input
    );
    Test.stopTest();

    System.assertEquals(
      'UP',
      saved.taxRoundingMode,
      'Core 第11.9節: 許可された税額丸めを保存結果へ返す'
    );
    System.assertEquals(
      'Scale2HalfUp',
      saved.quantityUnitPriceRoundingMode,
      'Core 第11.9節: 未指定の金額計算項目は現行のOrgDefaultを返す'
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
  static void saveSettingsRejectsMissingOrUnknownSendMode() {
    ContractDocumentSettingsController.SettingsDto input = new ContractDocumentSettingsController.SettingsDto();
    applyPdfOnlyRequired(input);
    input.estimateSendMode = null;

    Test.startTest();
    assertSaveRejected(
      input,
      '見積書の3択が無い、空、または不正です。',
      'Core 第11.3節: 見積書の3択は必須'
    );
    input.estimateSendMode = 'Unknown';
    assertSaveRejected(
      input,
      '見積書の3択が無い、空、または不正です。',
      'Core 第11.3節: 本文にない見積書の3択は拒否する'
    );
    Test.stopTest();
  }

  @IsTest
  static void saveSettingsWritesInputAndSystemHeadings() {
    ContractDocumentSettingsController.SettingsDto input = new ContractDocumentSettingsController.SettingsDto();
    applyPdfOnlyRequired(input);
    input.validationEnforce = true;
    input.lockExemptFieldApiNames = 'Memo__c,SentDate__c';
    input.paymentLockExemptFieldApiNames = 'Memo__c';
    input.journalLockExemptFieldApiNames = 'Memo__c';

    Test.startTest();
    ContractDocumentSettingsController.SettingsDto saved = saveWithFreshTokens(
      input
    );
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
    ContractValidationEnforce__c enforce = ContractValidationEnforce__c.getOrgDefaults();
    System.assertEquals(true, enforce.Enforce__c);
    InvoiceLockExemptFields__c lockExempt = InvoiceLockExemptFields__c.getOrgDefaults();
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
    InvoicePaymentLockExemptFields__c paymentLockExempt = InvoicePaymentLockExemptFields__c.getOrgDefaults();
    System.assertEquals('Memo__c', paymentLockExempt.FieldApiNames__c);
    GlJournalLockExemptFields__c journalLockExempt = GlJournalLockExemptFields__c.getOrgDefaults();
    System.assertEquals('Memo__c', journalLockExempt.FieldApiNames__c);
    ContractDocumentSettingsController.SettingsDto readback = ContractDocumentSettingsController.getSettings()
      .settings;
    System.assertEquals(true, readback.validationEnforce);
    System.assertEquals(
      'Memo__c,SentDate__c',
      readback.lockExemptFieldApiNames
    );
    System.assertEquals('Memo__c', readback.paymentLockExemptFieldApiNames);
    System.assertEquals('Memo__c', readback.journalLockExemptFieldApiNames);
  }

  @IsTest
  static void saveStoresEstimateAndInvoiceOrgSendersSeparately() {
    ContractDocumentSettingsController.SettingsDto input = new ContractDocumentSettingsController.SettingsDto();
    applyPdfOnlyRequired(input);
    input.estimateSendMode = 'PdfAndEmail';
    input.invoiceSendMode = 'PdfAndEmail';
    String orgSender = ContractTestDataFactory.requireVerifiedOrgWideAddress();
    input.estimateOrgWideEmailAddress = orgSender;
    input.invoiceOrgWideEmailAddress = orgSender;

    Test.startTest();
    ContractDocumentSettingsController.SettingsDto saved = saveWithFreshTokens(
      input
    );
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
    ContractDocumentSetting__c stored = [
      SELECT EstimateOrgWideEmailAddress__c, InvoiceOrgWideEmailAddress__c
      FROM ContractDocumentSetting__c
      WHERE SetupOwnerId = :UserInfo.getOrganizationId()
    ];
    System.assertEquals(orgSender, stored.EstimateOrgWideEmailAddress__c);
    System.assertEquals(orgSender, stored.InvoiceOrgWideEmailAddress__c);
    ContractDocumentSettingsController.SettingsDto readback = ContractDocumentSettingsController.getSettings()
      .settings;
    System.assertEquals(orgSender, readback.estimateOrgWideEmailAddress);
    System.assertEquals(orgSender, readback.invoiceOrgWideEmailAddress);
  }

  @IsTest
  static void saveRejectsInvoicePdfAndEmailWhenOnlyEstimateSenderSet() {
    ContractDocumentSettingsController.SettingsDto input = new ContractDocumentSettingsController.SettingsDto();
    applyPdfOnlyRequired(input);
    input.invoiceSendMode = 'PdfAndEmail';
    input.estimateOrgWideEmailAddress = ContractTestDataFactory.requireVerifiedOrgWideAddress();
    input.invoiceOrgWideEmailAddress = null;

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
  static void permissionIsRequiredForEveryControllerEntryPoint() {
    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.ORG_SETTINGS => false
    };

    Integer deniedCount = 0;
    Test.startTest();
    try {
      ContractDocumentSettingsController.getSettings();
      System.assert(false, '権限なしでは取得できないこと');
    } catch (AuraHandledException ex) {
      System.assert(ex.getMessage().contains('権限がありません'));
      deniedCount++;
    }
    try {
      ContractDocumentSettingsController.issueOrgSettingsOperationKey();
      System.assert(false, '権限なしでは業務操作キーを発行できないこと');
    } catch (AuraHandledException ex) {
      System.assert(ex.getMessage().contains('権限がありません'));
      deniedCount++;
    }
    try {
      ContractDocumentSettingsController.saveSettings(
        new ContractDocumentSettingsController.SettingsDto()
      );
      System.assert(false, '権限なしでは保存できないこと');
    } catch (AuraHandledException ex) {
      System.assert(ex.getMessage().contains('権限がありません'));
      deniedCount++;
    }
    try {
      ContractDocumentSettingsController.validateFieldCopyDefinitions();
      System.assert(false, '権限なしではコピー設定を検証できないこと');
    } catch (AuraHandledException ex) {
      System.assert(ex.getMessage().contains('権限がありません'));
      deniedCount++;
    }
    Test.stopTest();
    System.assertEquals(
      4,
      deniedCount,
      '共通基盤 第3章: 組織設定画面の全入口に20を要求する'
    );
  }

  @IsTest
  static void getSettings_includesAccountingMasterLinksWhenPermission21Assigned() {
    ContractDocumentSettingsController.testHasAccountingMaster = true;
    try {
      Test.startTest();
      ContractDocumentSettingsController.PageDataDto result = ContractDocumentSettingsController.getSettings();
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
