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
  static void requireSendMode_rejectsUnknownKindAndInvalidMode() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractTestDataFactory.ensureOrgDocumentSetting();
      ContractDocumentSettingService.clearCache();
      Boolean unknownKind = false;
      try {
        ContractDocumentSettingService.requireSendMode('Quote');
      } catch (ContractDocumentSettingService.SettingException ex) {
        unknownKind = true;
        System.assert(
          ex.getMessage().contains('見積書または請求書'),
          'Core 第11.3節: 見積書または請求書を指定する'
        );
      }
      System.assertEquals(true, unknownKind);

      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.InvoiceSendMode__c = 'MailOnly';
      update setting;
      ContractDocumentSettingService.clearCache();
      Boolean invalidMode = false;
      try {
        ContractDocumentSettingService.requireSendMode('Invoice');
      } catch (ContractDocumentSettingService.SettingException ex) {
        invalidMode = true;
        System.assertEquals(
          ContractDocumentSettingService.INVALID_SEND_MODE_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, invalidMode);
    }
  }

  @IsTest
  static void requireRenewOpportunitySwitch_readsOrgSetting() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.RenewOpportunityEnabled__c = true;
      update setting;
      ContractDocumentSettingService.clearCache();
      System.assertEquals(
        true,
        ContractDocumentSettingService.requireRenewOpportunitySwitch(),
        'Core 第11.5節: 更新商談スイッチは組織既定'
      );
      setting.RenewOpportunityEnabled__c = false;
      update setting;
      ContractDocumentSettingService.clearCache();
      System.assertEquals(
        false,
        ContractDocumentSettingService.requireRenewOpportunitySwitch()
      );
    }
  }

  @IsTest
  static void assertRequiredCompanyFields_invoiceRequiresRegistrationAndBank() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.InvoiceSendMode__c = ContractDocumentSettingService.MODE_PDF_ONLY;
      setting.EstimateSendMode__c = ContractDocumentSettingService.MODE_UNUSED;
      setting.CompanyName__c = '会社';
      setting.Address__c = '住所';
      setting.InvoiceRegistrationNumber__c = null;
      setting.BankTransferInfo__c = '振込先';
      update setting;
      ContractDocumentSettingService.clearCache();
      Boolean missingReg = false;
      try {
        ContractDocumentSettingService.assertRequiredCompanyFields();
      } catch (ContractDocumentSettingService.SettingException ex) {
        missingReg = true;
        System.assertEquals(
          ContractDocumentSettingService.MISSING_REGISTRATION_NUMBER_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, missingReg);

      setting.InvoiceRegistrationNumber__c = 'T123';
      setting.BankTransferInfo__c = null;
      update setting;
      ContractDocumentSettingService.clearCache();
      Boolean missingBank = false;
      try {
        ContractDocumentSettingService.assertRequiredCompanyFields();
      } catch (ContractDocumentSettingService.SettingException ex) {
        missingBank = true;
        System.assertEquals(
          ContractDocumentSettingService.MISSING_BANK_TRANSFER_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, missingBank);
    }
  }

  @IsTest
  static void assertRequiredCompanyFields_estimateRequiresAddress() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.EstimateSendMode__c = ContractDocumentSettingService.MODE_PDF_ONLY;
      setting.InvoiceSendMode__c = ContractDocumentSettingService.MODE_UNUSED;
      setting.CompanyName__c = '会社';
      setting.Address__c = null;
      update setting;
      ContractDocumentSettingService.clearCache();
      Boolean thrown = false;
      try {
        ContractDocumentSettingService.assertRequiredCompanyFields();
      } catch (ContractDocumentSettingService.SettingException ex) {
        thrown = true;
        System.assertEquals(
          ContractDocumentSettingService.MISSING_ADDRESS_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void assertModeCatalogRequirements_followsSendModeTable() {
    ContractDocumentSettingService.assertModeCatalogRequirements(
      ContractDocumentSettingService.MODE_UNUSED,
      null
    );
    ContractDocumentSettingService.assertModeCatalogRequirements(
      ContractDocumentSettingService.MODE_PDF_ONLY,
      null
    );
    ContractDocumentSettingService.assertModeCatalogRequirements(
      ContractDocumentSettingService.MODE_PDF_AND_EMAIL,
      'sender@example.com'
    );
    ContractDocumentSettingService.assertModeCatalogRequirements(
      ContractDocumentSettingService.MODE_PDF_AND_EMAIL,
      null,
      false
    );

    Boolean missingSender = false;
    try {
      ContractDocumentSettingService.assertModeCatalogRequirements(
        ContractDocumentSettingService.MODE_PDF_AND_EMAIL,
        null
      );
    } catch (ContractDocumentSettingService.SettingException ex) {
      missingSender = true;
      System.assertEquals(
        ContractDocumentSettingService.MISSING_ORG_SENDER_MESSAGE,
        ex.getMessage()
      );
    }
    System.assertEquals(true, missingSender);
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

  @IsTest
  static void withDocumentSendHeading_prefixesShortageBody() {
    System.assertEquals(
      '帳票・送付：会社名を設定してください。',
      ContractDocumentSettingService.withDocumentSendHeading(
        ContractDocumentSettingService.MISSING_COMPANY_NAME_MESSAGE
      ),
      'Core 第7.10節・第11.3.1節・第11.6節: 発行・送付・確定の不足エラーに見出し名を付ける'
    );
    System.assertEquals(
      '帳票・送付：会社名を設定してください。',
      ContractDocumentSettingService.withDocumentSendHeading(
        '帳票・送付：会社名を設定してください。'
      ),
      'Core 第7.10節: 見出し名は重ねない'
    );
  }
}
