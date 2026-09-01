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
      System.assert(
        ex.getMessage().contains('メールテンプレートAPI名が空です'),
        'Core 第11.3.2節: カタログ行のAPI名は空にしない。実際: ' + ex.getMessage()
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
      System.assert(
        ex.getMessage().contains('帳票種別が不正です'),
        'Core 第11.3.2節: 帳票種別は見積または請求。実際: ' + ex.getMessage()
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void resolveForOperation_usesOrgDefaultWhenRequestedBlank() {
    ContractEmailTemplateService.clearTestState();
    ContractEmailTemplateService.seedActiveRowForTest(
      ContractEmailTemplateService.TYPE_INVOICE,
      'InvoiceMail'
    );
    ContractEmailTemplateService.EmailTemplateDefinition resolved =
      ContractEmailTemplateService.resolveForOperation(
        ContractEmailTemplateService.TYPE_INVOICE,
        '  ',
        'InvoiceMail'
      );
    System.assertEquals(
      'InvoiceMail',
      resolved.apiName,
      'Core 第11.3.2節: 指定が空なら組織既定のカタログ行を使う'
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
}
