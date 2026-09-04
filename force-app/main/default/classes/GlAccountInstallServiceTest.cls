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

      InvoiceLockExemptFields__c lockExempt = InvoiceLockExemptFields__c.getOrgDefaults();
      System.assertNotEquals(null, lockExempt.Id, '仕様: Core 第11.6節 ロック除外をシード');
      System.assertEquals(
        InvoiceLockUtil.SEED_LOCK_EXEMPT_FIELDS,
        lockExempt.FieldApiNames__c,
        '仕様: Core 第11.6節 指定9項目'
      );
      InvoicePaymentLockExemptFields__c paymentLockExempt =
        InvoicePaymentLockExemptFields__c.getOrgDefaults();
      System.assertNotEquals(
        null,
        paymentLockExempt.Id,
        '仕様: Core 第11.6節 入出金ロック除外をシード'
      );
      System.assertEquals(
        InvoicePaymentLockUtil.SEED_LOCK_EXEMPT_FIELDS,
        paymentLockExempt.FieldApiNames__c,
        '仕様: Core 第11.6節 入出金シード Memo__c'
      );
      GlJournalLockExemptFields__c journalLockExempt =
        GlJournalLockExemptFields__c.getOrgDefaults();
      System.assertNotEquals(
        null,
        journalLockExempt.Id,
        '仕様: Core 第11.6節 仕訳ロック除外をシード'
      );
      System.assertEquals(
        JournalLockService.SEED_LOCK_EXEMPT_FIELDS,
        journalLockExempt.FieldApiNames__c,
        '仕様: Core 第11.6節 仕訳シード Memo__c'
      );

      ContractDocumentSetting__c setting = ContractDocumentSetting__c.getOrgDefaults();
      System.assertNotEquals(null, setting.Id, '仕様: Core 第11.6節 組織設定をシード');
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
