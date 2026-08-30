@IsTest
private class ContractDocumentSettingServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void requireEstimateValidMonths_readsOrgSetting() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractTestDataFactory.ensureOrgDocumentSetting();
      ContractDocumentSettingService.clearCache();
      System.assertEquals(
        1,
        ContractDocumentSettingService.requireEstimateValidMonths()
      );
    }
  }

  @IsTest
  static void requireEstimateValidMonths_rejectsOutOfRange() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.EstimateValidMonths__c = 0;
      update setting;
      ContractDocumentSettingService.clearCache();
      Boolean thrown = false;
      try {
        ContractDocumentSettingService.requireEstimateValidMonths();
      } catch (ContractDocumentSettingService.SettingException ex) {
        thrown = true;
        System.assert(ex.getMessage().contains('見積有効期間'));
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void requireDefaultCycles_readsOrgSetting() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractTestDataFactory.ensureOrgDocumentSetting();
      ContractDocumentSettingService.clearCache();
      System.assertEquals(12, ContractDocumentSettingService.requireDefaultCycles());
    }
  }

  @IsTest
  static void requireDefaultCycles_rejectsOutOfRange() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.DefaultMonthlyCycles__c = 37;
      update setting;
      ContractDocumentSettingService.clearCache();
      Boolean thrown = false;
      try {
        ContractDocumentSettingService.requireDefaultCycles();
      } catch (ContractDocumentSettingService.SettingException ex) {
        thrown = true;
        System.assert(ex.getMessage().contains('既定サイクル数'));
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void requireSendMode_readsOrgDefault_ignoresUserHierarchyRow() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c orgSetting = ContractTestDataFactory.ensureOrgDocumentSetting();
      orgSetting.EstimateSendMode__c = ContractDocumentSettingService.MODE_PDF_AND_EMAIL;
      update orgSetting;
      insert new ContractDocumentSetting__c(
        Name = 'UserOverride',
        SetupOwnerId = UserInfo.getUserId(),
        EstimateSendMode__c = ContractDocumentSettingService.MODE_UNUSED,
        InvoiceSendMode__c = ContractDocumentSettingService.MODE_UNUSED,
        EstimateValidMonths__c = 1,
        DefaultMonthlyCycles__c = 12
      );
      ContractDocumentSettingService.clearCache();
      System.assertEquals(
        ContractDocumentSettingService.MODE_PDF_AND_EMAIL,
        ContractDocumentSettingService.requireSendMode('Estimate'),
        'Core 第11.6節: 製品は組織既定だけを読む。ユーザー行は見ない'
      );
    }
  }

  @IsTest
  static void sendModes_areTextOnHierarchySetting() {
    System.assertEquals(
      Schema.DisplayType.STRING,
      ContractDocumentSetting__c.EstimateSendMode__c.getDescribe().getType()
    );
    System.assertEquals(
      Schema.DisplayType.STRING,
      ContractDocumentSetting__c.InvoiceSendMode__c.getDescribe().getType()
    );
  }
}
