@IsTest
private class ContractEmailTemplateServiceTest {
  @IsTest
  static void getActiveTemplates_emptyCatalog_returnsEmpty() {
    ContractEmailTemplateService.clearTestState();
    ContractEmailTemplateService.testRecords = new List<ContractEmailTemplate__mdt>();
    List<ContractEmailTemplateService.EmailTemplateDefinition> rows =
      ContractEmailTemplateService.getActiveTemplates(
        ContractEmailTemplateService.TYPE_ESTIMATE
      );
    System.assertEquals(
      0,
      rows.size(),
      'Core 第11.3.2節: 同梱行は置かない。有効行が無ければ空'
    );
  }

  @IsTest
  static void getActiveTemplates_duplicateApiName_throws() {
    ContractEmailTemplateService.clearTestState();
    ContractEmailTemplateService.seedActiveRowForTest(
      ContractEmailTemplateService.TYPE_ESTIMATE,
      'EstimateMail'
    );
    ContractEmailTemplateService.seedActiveRowForTest(
      ContractEmailTemplateService.TYPE_ESTIMATE,
      'EstimateMail'
    );
    Boolean thrown = false;
    try {
      ContractEmailTemplateService.getActiveTemplates(
        ContractEmailTemplateService.TYPE_ESTIMATE
      );
    } catch (ContractEmailTemplateService.EmailTemplateException ex) {
      thrown = true;
      System.assertEquals(
        ContractEmailTemplateService.DUPLICATE_API_NAME_MESSAGE,
        ex.getMessage(),
        'Core 第11.3.2節: 同じ種別の有効行が同じAPI名を複数持たない'
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void resolveTemplate_unknownApiName_throws() {
    ContractEmailTemplateService.clearTestState();
    Boolean thrown = false;
    try {
      ContractEmailTemplateService.resolveTemplate(
        ContractEmailTemplateService.TYPE_INVOICE,
        'NotInCatalog'
      );
    } catch (ContractEmailTemplateService.EmailTemplateException ex) {
      thrown = true;
      System.assertEquals(
        ContractEmailTemplateService.NOT_IN_CATALOG_MESSAGE,
        ex.getMessage(),
        'Core 第11.3.2節: 候補に無いメールはエラー'
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void resolveForOperation_blank_throws() {
    Boolean thrown = false;
    try {
      ContractEmailTemplateService.resolveForOperation(
        ContractEmailTemplateService.TYPE_ESTIMATE,
        null,
        null
      );
    } catch (ContractEmailTemplateService.EmailTemplateException ex) {
      thrown = true;
      System.assertEquals(
        ContractEmailTemplateService.MISSING_API_NAME_MESSAGE,
        ex.getMessage(),
        'Core 第11.3.2節: PDFとメール送付でテンプレ無しの本文は作らない'
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void resolveOrgWide_blank_throws() {
    Boolean thrown = false;
    try {
      ContractEmailTemplateService.resolveOrgWide(null);
    } catch (ContractEmailTemplateService.EmailTemplateException ex) {
      thrown = true;
      System.assertEquals(
        ContractDocumentSettingService.MISSING_ORG_SENDER_MESSAGE,
        ex.getMessage(),
        'Core 第11.3.2節: 未設定はエラー'
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void resolveOrgWide_unknownAddress_throws() {
    Boolean thrown = false;
    try {
      ContractEmailTemplateService.resolveOrgWide('nosuch-sender@example.com');
    } catch (ContractEmailTemplateService.EmailTemplateException ex) {
      thrown = true;
      System.assertEquals(
        ContractDocumentSettingService.ORG_SENDER_NOT_FOUND_MESSAGE,
        ex.getMessage(),
        'Core 第11.3.2節: 検証済み組織ワイドメール0件はエラー'
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void getActiveTemplates_rejectsBlankApiName() {
    ContractEmailTemplateService.clearTestState();
    ContractEmailTemplateService.testRecords = new List<ContractEmailTemplate__mdt>{
      new ContractEmailTemplate__mdt(
        MasterLabel = '空API',
        DocumentType__c = ContractEmailTemplateService.TYPE_ESTIMATE,
        EmailTemplateApiName__c = '',
        IsActive__c = true,
        SortOrder__c = 1
      )
    };
    Boolean thrown = false;
    try {
      ContractEmailTemplateService.getActiveTemplates(
        ContractEmailTemplateService.TYPE_ESTIMATE
      );
    } catch (ContractEmailTemplateService.EmailTemplateException ex) {
      thrown = true;
      System.assertEquals(
        '空API のメールテンプレートAPI名が空です。',
        ex.getMessage(),
        'Core 第11.3.2節: カタログ行のAPI名は空にしない'
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void getActiveTemplates_rejectsUnknownDocumentType() {
    Boolean thrown = false;
    try {
      ContractEmailTemplateService.getActiveTemplates('UnknownType');
    } catch (ContractEmailTemplateService.EmailTemplateException ex) {
      thrown = true;
      System.assertEquals(
        '帳票種別が不正です: UnknownType',
        ex.getMessage(),
        'Core 第11.3.2節: 帳票種別は見積または請求'
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void resolveForOperation_blank_doesNotFillOrgDefault() {
    ContractEmailTemplateService.clearTestState();
    ContractEmailTemplateService.seedActiveRowForTest(
      ContractEmailTemplateService.TYPE_INVOICE,
      'InvoiceMail'
    );
    Boolean thrown = false;
    try {
      ContractEmailTemplateService.resolveForOperation(
        ContractEmailTemplateService.TYPE_INVOICE,
        '  ',
        'InvoiceMail'
      );
    } catch (ContractEmailTemplateService.EmailTemplateException ex) {
      thrown = true;
      System.assertEquals(
        ContractEmailTemplateService.MISSING_API_NAME_MESSAGE,
        ex.getMessage(),
        'Core 第11.3.2節: 指定が空なら組織既定では埋めない'
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void initialSelectionApiName_oneDefault_returnsApiName() {
    ContractEmailTemplateService.clearTestState();
    ContractEmailTemplate__mdt row = new ContractEmailTemplate__mdt();
    row.MasterLabel = 'InvoiceMail';
    row.DocumentType__c = ContractEmailTemplateService.TYPE_INVOICE;
    row.EmailTemplateApiName__c = 'InvoiceMail';
    row.IsActive__c = true;
    row.IsDefault__c = true;
    row.SortOrder__c = 1;
    ContractEmailTemplateService.testRecords = new List<ContractEmailTemplate__mdt>{
      row
    };
    ContractEmailTemplateService.skipSalesforceTemplateLookup = true;
    System.assertEquals(
      'InvoiceMail',
      ContractEmailTemplateService.initialSelectionApiName(
        ContractEmailTemplateService.TYPE_INVOICE
      ),
      'Core 第11.3.2節: 有効な既定がちょうど1つなら初期選択'
    );
  }

  @IsTest
  static void initialSelectionApiName_zeroOrMany_returnsNull() {
    ContractEmailTemplateService.clearTestState();
    ContractEmailTemplateService.seedActiveRowForTest(
      ContractEmailTemplateService.TYPE_INVOICE,
      'InvoiceMail'
    );
    System.assertEquals(
      null,
      ContractEmailTemplateService.initialSelectionApiName(
        ContractEmailTemplateService.TYPE_INVOICE
      ),
      'Core 第11.3.2節: 有効な既定0件なら未選択'
    );

    ContractEmailTemplate__mdt first = new ContractEmailTemplate__mdt();
    first.MasterLabel = 'A';
    first.DocumentType__c = ContractEmailTemplateService.TYPE_INVOICE;
    first.EmailTemplateApiName__c = 'A';
    first.IsActive__c = true;
    first.IsDefault__c = true;
    first.SortOrder__c = 1;
    ContractEmailTemplate__mdt second = new ContractEmailTemplate__mdt();
    second.MasterLabel = 'B';
    second.DocumentType__c = ContractEmailTemplateService.TYPE_INVOICE;
    second.EmailTemplateApiName__c = 'B';
    second.IsActive__c = true;
    second.IsDefault__c = true;
    second.SortOrder__c = 2;
    ContractEmailTemplateService.testRecords = new List<ContractEmailTemplate__mdt>{
      first,
      second
    };
    System.assertEquals(
      null,
      ContractEmailTemplateService.initialSelectionApiName(
        ContractEmailTemplateService.TYPE_INVOICE
      ),
      'Core 第11.3.2節: 有効な既定2件以上なら未選択'
    );
  }

  @IsTest
  static void resolveTemplate_missingSalesforceTemplate_throws() {
    ContractEmailTemplateService.clearTestState();
    ContractEmailTemplateService.seedActiveRowForTest(
      ContractEmailTemplateService.TYPE_ESTIMATE,
      'NoSalesforceTemplate'
    );
    ContractEmailTemplateService.skipSalesforceTemplateLookup = false;
    Boolean thrown = false;
    try {
      ContractEmailTemplateService.resolveTemplate(
        ContractEmailTemplateService.TYPE_ESTIMATE,
        'NoSalesforceTemplate'
      );
    } catch (ContractEmailTemplateService.EmailTemplateException ex) {
      thrown = true;
      System.assertEquals(
        ContractEmailTemplateService.INVALID_SALESFORCE_TEMPLATE_MESSAGE,
        ex.getMessage(),
        'Core 第11.3.2節: 候補に無いClassicテキストはエラー'
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void initialSelectionApiName_bundledRowIsExactlyOneDefault() {
    ContractEmailTemplateService.clearTestState();
    System.assertEquals(
      'Contract_Standard_Estimate_Email',
      ContractEmailTemplateService.initialSelectionApiName(
        ContractEmailTemplateService.TYPE_ESTIMATE
      ),
      'Core 第11.3.2節: 同梱は有効な既定ちょうど1つ'
    );
    System.assertEquals(
      'Contract_Standard_Invoice_Email',
      ContractEmailTemplateService.initialSelectionApiName(
        ContractEmailTemplateService.TYPE_INVOICE
      ),
      'Core 第11.3.2節: 請求も同梱は有効な既定ちょうど1つ'
    );
  }

  @IsTest
  static void renderForSend_inTestLeavesBodyBlank() {
    ContractEmailTemplateService.clearTestState();
    ContractEmailTemplateService.seedActiveRowForTest(
      ContractEmailTemplateService.TYPE_ESTIMATE,
      'EstimateMail'
    );
    ContractEmailTemplateService.MergeResult rendered =
      ContractEmailTemplateService.renderForSend(
        ContractEmailTemplateService.TYPE_ESTIMATE,
        'EstimateMail',
        null,
        null
      );
    System.assertEquals('EstimateMail', rendered.apiName);
    System.assertEquals(
      '',
      rendered.subject,
      'Core 第7.10節: テスト実行では本文マージをしない'
    );
    System.assertEquals('', rendered.body);
  }

  @IsTest
  static void formatOrgWideFrom_usesDisplayNameWhenPresent() {
    System.assertEquals(
      '',
      ContractEmailTemplateService.formatOrgWideFrom(null),
      'Core 第7.10節: Fromは組織送信元の参照'
    );
    ContractEmailTemplateService.OrgWideResolved blankAddress =
      new ContractEmailTemplateService.OrgWideResolved();
    System.assertEquals(
      '',
      ContractEmailTemplateService.formatOrgWideFrom(blankAddress)
    );
    blankAddress.address = 'ops@example.com';
    System.assertEquals(
      'ops@example.com',
      ContractEmailTemplateService.formatOrgWideFrom(blankAddress)
    );
    blankAddress.displayName = '運用';
    System.assertEquals(
      '運用 <ops@example.com>',
      ContractEmailTemplateService.formatOrgWideFrom(blankAddress)
    );
  }

  @IsTest
  static void resolveTemplate_trimsApiName() {
    ContractEmailTemplateService.clearTestState();
    ContractEmailTemplateService.seedActiveRowForTest(
      ContractEmailTemplateService.TYPE_INVOICE,
      'InvoiceMail'
    );
    ContractEmailTemplateService.EmailTemplateDefinition matched =
      ContractEmailTemplateService.resolveTemplate(
        ContractEmailTemplateService.TYPE_INVOICE,
        ' InvoiceMail '
      );
    System.assertEquals(
      'InvoiceMail',
      matched.apiName,
      'Core 第11.3.2節: 指定の送付メールは前後空白を除いてカタログと照合する'
    );
  }

  @IsTest
  static void renderForSend_withWhoId_stillLeavesBodyBlankInTest() {
    ContractEmailTemplateService.clearTestState();
    ContractEmailTemplateService.seedActiveRowForTest(
      ContractEmailTemplateService.TYPE_ESTIMATE,
      'EstimateMailWho'
    );
    ContractEmailTemplateService.MergeResult rendered =
      ContractEmailTemplateService.renderForSend(
        ContractEmailTemplateService.TYPE_ESTIMATE,
        'EstimateMailWho',
        'ignored-org-default',
        UserInfo.getUserId(),
        UserInfo.getUserId()
      );
    System.assertEquals('EstimateMailWho', rendered.apiName);
    System.assertEquals(
      '',
      rendered.body,
      'Core 第7.10節: テスト実行では本文マージをしない。組織既定では埋めない'
    );
  }

  @IsTest
  static void getActiveTemplates_skipsInactiveRows() {
    ContractEmailTemplateService.clearTestState();
    ContractEmailTemplateService.seedActiveRowForTest(
      ContractEmailTemplateService.TYPE_ESTIMATE,
      'ActiveMail'
    );
    ContractEmailTemplate__mdt inactive = new ContractEmailTemplate__mdt();
    inactive.MasterLabel = 'InactiveMail';
    inactive.DocumentType__c = ContractEmailTemplateService.TYPE_ESTIMATE;
    inactive.EmailTemplateApiName__c = 'InactiveMail';
    inactive.IsActive__c = false;
    inactive.IsDefault__c = true;
    inactive.SortOrder__c = 0;
    ContractEmailTemplateService.testRecords.add(inactive);
    List<ContractEmailTemplateService.EmailTemplateDefinition> rows =
      ContractEmailTemplateService.getActiveTemplates(
        ContractEmailTemplateService.TYPE_ESTIMATE
      );
    System.assertEquals(
      1,
      rows.size(),
      'Core 第11.3.2節: 無効行は候補に出さない'
    );
    System.assertEquals('ActiveMail', rows[0].apiName);
    System.assertEquals(
      null,
      ContractEmailTemplateService.initialSelectionApiName(
        ContractEmailTemplateService.TYPE_ESTIMATE
      ),
      'Core 第11.3.2節: 有効な既定がちょうど1つでなければ未選択'
    );
  }
}
