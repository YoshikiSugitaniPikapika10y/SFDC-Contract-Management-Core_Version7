@IsTest
private class GlAccountInstallServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void seedOnInstall_isIdempotent() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountInstallService.seedOnInstall();
      GlAccountInstallService.seedOnInstall();
      System.assertEquals(
        7,
        [
          SELECT COUNT()
          FROM GlAccount__c
          WHERE
            Name IN (
              '売掛金',
              '仮受金',
              '為替差益',
              '為替差損',
              '支払手数料',
              '雑収入',
              '貸倒損失'
            )
        ],
        'Accounting 第4.1節: 初回インストールだけ7科目を作り、アップグレードでは再作成しない'
      );
      System.assertEquals(
        5,
        [SELECT COUNT() FROM GlManualJournalSetting__c],
        'Accounting 第4.1節: 手動仕訳設定シードは1回だけ'
      );
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM FieldCopyDefinition__c
          WHERE Name = 'Sample_Inv_AccountName'
        ],
        '仕様: Core 第11.4.2節 Sample_Inv_AccountName'
      );
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM FieldCopyDefinition__c
          WHERE Name = 'Sample_Line_ProductCode'
        ],
        '仕様: Core 第11.4.2節 Sample_Line_ProductCode'
      );
      FieldCopyDefinition__c lineSample = [
        SELECT
          SourceObject__c,
          SourceFieldApiName__c,
          TargetObject__c,
          TargetFieldApiName__c
        FROM FieldCopyDefinition__c
        WHERE Name = 'Sample_Line_ProductCode'
        LIMIT 1
      ];
      System.assertEquals(
        'Product2',
        lineSample.SourceObject__c,
        '仕様: Core 第11.4.2節 Sample_Line_ProductCode From=Product2.ProductCode'
      );
      System.assertEquals(
        'ProductCode',
        lineSample.SourceFieldApiName__c,
        '仕様: Core 第11.4.2節 Sample_Line_ProductCode From=Product2.ProductCode'
      );
      System.assertEquals(
        'InvoiceLine__c',
        lineSample.TargetObject__c,
        '仕様: Core 第11.4.2節 Sample_Line_ProductCode To=請求明細'
      );
      System.assertEquals(
        'ProductCodeSnapShot__c',
        lineSample.TargetFieldApiName__c,
        '仕様: Core 第11.4.2節 Sample_Line_ProductCode To=商品コード SnapShot'
      );
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM FieldCopyDefinition__c
          WHERE Name = 'Sample_Journal_ProductCode'
        ],
        '仕様: Core 第11.4.2節 Sample_Journal_ProductCode'
      );
      FieldCopyDefinition__c journalSample = [
        SELECT
          SourceObject__c,
          SourceFieldApiName__c,
          TargetObject__c,
          TargetFieldApiName__c,
          Context__c
        FROM FieldCopyDefinition__c
        WHERE Name = 'Sample_Journal_ProductCode'
        LIMIT 1
      ];
      System.assertEquals(
        'Product2',
        journalSample.SourceObject__c,
        '仕様: Core 第11.4.2節 From=Product2.ProductCode'
      );
      System.assertEquals(
        'ProductCode',
        journalSample.SourceFieldApiName__c,
        '仕様: Core 第11.4.2節 From=Product2.ProductCode'
      );
      System.assertEquals(
        'GlJournal__c',
        journalSample.TargetObject__c,
        '仕様: Core 第11.4.2節 To=GlJournal.ProductCodeSnapShot'
      );
      System.assertEquals(
        'ProductCodeSnapShot__c',
        journalSample.TargetFieldApiName__c,
        '仕様: Core 第11.4.2節 To=商品コード SnapShot'
      );
      System.assertEquals(
        FieldCopyDefinitionService.CONTEXT_LINE_JOURNAL,
        journalSample.Context__c,
        '仕様: Core 第11.4.2節 コンテキストは明細仕訳'
      );
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM FieldCopyDefinition__c
          WHERE Name = 'Sample_Period_AccountName'
        ],
        '仕様: Core 第11.4.2節 Period見本は置かない'
      );
      Map<String, GlAccount__c> seeded = new Map<String, GlAccount__c>();
      for (GlAccount__c account : [
        SELECT Name, AccountType__c, AccountCode__c, IsActive__c
        FROM GlAccount__c
        WHERE
          Name IN (
            '売掛金',
            '仮受金',
            '為替差益',
            '為替差損',
            '支払手数料',
            '雑収入',
            '貸倒損失'
          )
      ]) {
        seeded.put(account.Name, account);
      }
      System.assertEquals(
        'Asset',
        seeded.get('売掛金').AccountType__c,
        'Accounting 第4.1節: 売掛金は資産'
      );
      System.assertEquals(
        'Liability',
        seeded.get('仮受金').AccountType__c,
        'Accounting 第4.1節: 仮受金は負債'
      );
      System.assertEquals(
        'Revenue',
        seeded.get('為替差益').AccountType__c,
        'Accounting 第4.1節: 為替差益は収益'
      );
      System.assertEquals(
        'Expense',
        seeded.get('為替差損').AccountType__c,
        'Accounting 第4.1節: 為替差損は費用'
      );
      System.assertEquals(
        'Expense',
        seeded.get('支払手数料').AccountType__c,
        'Accounting 第4.1節: 支払手数料は費用'
      );
      System.assertEquals(
        'Revenue',
        seeded.get('雑収入').AccountType__c,
        'Accounting 第4.1節: 雑収入は収益'
      );
      System.assertEquals(
        'Expense',
        seeded.get('貸倒損失').AccountType__c,
        'Accounting 第4.1節: 貸倒損失は費用'
      );
      for (GlAccount__c account : seeded.values()) {
        System.assertEquals(
          true,
          String.isBlank(account.AccountCode__c),
          'Accounting 第4.1節: シード科目のコードは空欄'
        );
        System.assertEquals(
          true,
          account.IsActive__c,
          'Accounting 第4.1節: 有効の既定True'
        );
      }
      Map<String, GlManualJournalSetting__c> manuals = new Map<String, GlManualJournalSetting__c>();
      for (GlManualJournalSetting__c setting : [
        SELECT
          SettingKey__c,
          Name,
          DebitAccount__c,
          CreditAccount__c,
          Description__c,
          IsActive__c
        FROM GlManualJournalSetting__c
      ]) {
        manuals.put(setting.SettingKey__c, setting);
      }
      System.assertEquals(
        '為替差損の計上',
        manuals.get('FX_LOSS').Name,
        'Accounting 第10.2節: FX_LOSS'
      );
      System.assertEquals(
        seeded.get('為替差損').Id,
        manuals.get('FX_LOSS').DebitAccount__c,
        'Accounting 第4.1節: 手動仕訳設定へ作成した科目IDを設定する'
      );
      System.assertEquals(
        seeded.get('売掛金').Id,
        manuals.get('FX_LOSS').CreditAccount__c,
        'Accounting 第4.1節: 手動仕訳設定へ作成した科目IDを設定する'
      );
      System.assertEquals(
        '入金不足が為替変動による場合',
        manuals.get('FX_LOSS').Description__c,
        'Accounting 第10.2節: FX_LOSS の用途'
      );
      System.assertEquals(
        true,
        manuals.get('FX_LOSS').IsActive__c,
        'Accounting 第10.2節: 有効の既定True'
      );
      System.assertEquals(
        '為替差益の計上',
        manuals.get('FX_GAIN').Name,
        'Accounting 第10.2節: FX_GAIN'
      );
      System.assertEquals(
        seeded.get('仮受金').Id,
        manuals.get('FX_GAIN').DebitAccount__c,
        'Accounting 第4.1節: 手動仕訳設定へ作成した科目IDを設定する'
      );
      System.assertEquals(
        seeded.get('為替差益').Id,
        manuals.get('FX_GAIN').CreditAccount__c,
        'Accounting 第4.1節: 手動仕訳設定へ作成した科目IDを設定する'
      );
      System.assertEquals(
        '振込手数料の当社負担',
        manuals.get('BANK_FEE_ABSORBED').Name,
        'Accounting 第10.2節: BANK_FEE_ABSORBED'
      );
      System.assertEquals(
        seeded.get('支払手数料').Id,
        manuals.get('BANK_FEE_ABSORBED').DebitAccount__c,
        'Accounting 第4.1節: 手動仕訳設定へ作成した科目IDを設定する'
      );
      System.assertEquals(
        '過入金の収益化',
        manuals.get('OVERPAYMENT_INCOME').Name,
        'Accounting 第10.2節: OVERPAYMENT_INCOME'
      );
      System.assertEquals(
        '貸倒の計上',
        manuals.get('BAD_DEBT').Name,
        'Accounting 第10.2節: BAD_DEBT'
      );
    }
  }

  @IsTest
  static void seedOnInstall_upgradeDoesNotRecreateDeletedManualSettings() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountInstallService.seedOnInstall();
      delete [SELECT Id FROM GlManualJournalSetting__c];
      System.assertEquals(
        0,
        [SELECT COUNT() FROM GlManualJournalSetting__c],
        '前提: テナントがシードを削除した'
      );
      GlAccountInstallService.forceUpgradeSeedPath = true;
      try {
        GlAccountInstallService.seedOnInstall();
      } finally {
        GlAccountInstallService.forceUpgradeSeedPath = false;
      }
      System.assertEquals(
        0,
        [SELECT COUNT() FROM GlManualJournalSetting__c],
        'Accounting 第10.2節: 削除後のアップグレードで手動仕訳設定を自動再作成しない'
      );
    }
  }

  @IsTest
  static void seedOnInstall_upgradeDoesNotRecreateDeletedFieldCopySamples() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountInstallService.seedOnInstall();
      delete [SELECT Id FROM FieldCopyDefinition__c];
      System.assertEquals(
        0,
        [SELECT COUNT() FROM FieldCopyDefinition__c],
        '前提: テナントが見本を削除した'
      );
      GlAccountInstallService.forceUpgradeSeedPath = true;
      try {
        GlAccountInstallService.seedOnInstall();
      } finally {
        GlAccountInstallService.forceUpgradeSeedPath = false;
      }
      System.assertEquals(
        0,
        [SELECT COUNT() FROM FieldCopyDefinition__c],
        'Core 第11.4.2節: 削除後のアップグレードでは見本を戻さない'
      );
    }
  }

  @IsTest
  static void seedOnInstall_upgradeDoesNotRecreateDeletedOrgDefaults() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountInstallService.seedOnInstall();
      delete [
        SELECT Id
        FROM ContractDocumentSetting__c
        WHERE SetupOwnerId = :UserInfo.getOrganizationId()
      ];
      delete [
        SELECT Id
        FROM InvoiceLockExemptFields__c
        WHERE SetupOwnerId = :UserInfo.getOrganizationId()
      ];
      delete [
        SELECT Id
        FROM InvoicePaymentLockExemptFields__c
        WHERE SetupOwnerId = :UserInfo.getOrganizationId()
      ];
      delete [
        SELECT Id
        FROM GlJournalLockExemptFields__c
        WHERE SetupOwnerId = :UserInfo.getOrganizationId()
      ];
      ContractDocumentSettingService.clearCache();
      GlAccountInstallService.forceUpgradeSeedPath = true;
      try {
        GlAccountInstallService.seedOnInstall();
      } finally {
        GlAccountInstallService.forceUpgradeSeedPath = false;
      }
      System.assertEquals(
        null,
        ContractDocumentSetting__c.getOrgDefaults().Id,
        'Core 第11.6節: 人が消したあとのアップグレードでは組織既定を戻さない'
      );
      System.assertEquals(
        null,
        InvoiceLockExemptFields__c.getOrgDefaults().Id,
        'Core 第11.6節: 人が消したあとのアップグレードでは請求ロック除外を戻さない'
      );
      System.assertEquals(
        null,
        InvoicePaymentLockExemptFields__c.getOrgDefaults().Id,
        'Core 第11.6節: 人が消したあとのアップグレードでは入出金ロック除外を戻さない'
      );
      System.assertEquals(
        null,
        GlJournalLockExemptFields__c.getOrgDefaults().Id,
        'Core 第11.6節: 人が消したあとのアップグレードでは仕訳ロック除外を戻さない'
      );
    }
  }

  @IsTest
  static void seedOnInstall_seedsLockExemptAndOrgDocumentSetting() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      delete [
        SELECT Id
        FROM InvoiceLockExemptFields__c
        WHERE SetupOwnerId = :UserInfo.getOrganizationId()
      ];
      delete [
        SELECT Id
        FROM InvoicePaymentLockExemptFields__c
        WHERE SetupOwnerId = :UserInfo.getOrganizationId()
      ];
      delete [
        SELECT Id
        FROM GlJournalLockExemptFields__c
        WHERE SetupOwnerId = :UserInfo.getOrganizationId()
      ];
      delete [
        SELECT Id
        FROM ContractDocumentSetting__c
        WHERE SetupOwnerId = :UserInfo.getOrganizationId()
      ];
      ContractDocumentSettingService.clearCache();

      GlAccountInstallService.seedOnInstall();
      GlAccountInstallService.seedOnInstall();

      System.assertEquals(
        null,
        InvoiceLockExemptFields__c.getOrgDefaults().Id,
        'Core 第11.6節: 初回インストールでも請求ロック除外は作らない'
      );
      System.assertEquals(
        null,
        InvoicePaymentLockExemptFields__c.getOrgDefaults().Id,
        'Core 第11.6節: 初回インストールでも入出金ロック除外は作らない'
      );
      System.assertEquals(
        null,
        GlJournalLockExemptFields__c.getOrgDefaults().Id,
        'Core 第11.6節: 初回インストールでも仕訳ロック除外は作らない'
      );

      ContractDocumentSetting__c setting = ContractDocumentSetting__c.getOrgDefaults();
      System.assertNotEquals(
        null,
        setting.Id,
        '仕様: Core 第11.6節 組織設定をシード'
      );
      System.assertEquals(
        ContractDocumentSettingService.MODE_PDF_ONLY,
        setting.EstimateSendMode__c,
        '仕様: Core 第4.10節・第11.8節 見積書 PDFのみ'
      );
      System.assertEquals(
        ContractDocumentSettingService.MODE_PDF_ONLY,
        setting.InvoiceSendMode__c,
        '仕様: Core 第4.10節・第11.8節 請求書 PDFのみ'
      );
      System.assertEquals(
        12,
        Integer.valueOf(setting.DefaultMonthlyCycles__c),
        '仕様: Core 第11.6節 既定サイクル数12'
      );
      System.assertEquals(
        1,
        Integer.valueOf(setting.EstimateValidMonths__c),
        '仕様: Core 第11.6節 見積有効期間1'
      );
      System.assertEquals(
        false,
        setting.RenewOpportunityEnabled__c,
        '仕様: Core 第11.5節・第11.6節 更新商談スイッチOFF'
      );
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM ContractDocumentSetting__c
          WHERE SetupOwnerId = :UserInfo.getOrganizationId()
        ],
        '仕様: 組織設定シードは1件だけ'
      );
    }
  }
}
