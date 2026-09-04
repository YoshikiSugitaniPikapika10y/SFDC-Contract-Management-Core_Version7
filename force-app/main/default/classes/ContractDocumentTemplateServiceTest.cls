@IsTest
private class ContractDocumentTemplateServiceTest {
  @IsTest
  static void standardTemplatesAreSeededForBothTypes() {
    ContractDocumentTemplateService.TemplateDefinition estimate = ContractDocumentTemplateService.resolveTemplate(
      ContractDocumentTemplateService.TYPE_ESTIMATE,
      ContractDocumentTemplateService.DEFAULT_ESTIMATE_KEY
    );
    ContractDocumentTemplateService.TemplateDefinition invoice = ContractDocumentTemplateService.resolveTemplate(
      ContractDocumentTemplateService.TYPE_INVOICE,
      ContractDocumentTemplateService.DEFAULT_INVOICE_KEY
    );

    System.assertEquals(
      ContractDocumentTemplateService.DEFAULT_ESTIMATE_KEY,
      estimate.templateKey
    );
    System.assertEquals('EstimateDocumentPdf', estimate.visualforcePage);
    System.assertEquals(
      ContractDocumentTemplateService.DEFAULT_INVOICE_KEY,
      invoice.templateKey
    );
    System.assertEquals('InvoiceDocumentPdf', invoice.visualforcePage);
  }

  @IsTest
  static void resolveTemplate_blankKeyDoesNotFillCatalogFirst() {
    Boolean thrown = false;
    try {
      ContractDocumentTemplateService.resolveTemplate(
        ContractDocumentTemplateService.TYPE_ESTIMATE,
        null
      );
    } catch (
      ContractDocumentTemplateService.DocumentTemplateException ex
    ) {
      thrown = true;
      System.assertEquals(
        ContractDocumentSettingService.MISSING_DEFAULT_DOCUMENT_MESSAGE,
        ex.getMessage(),
        'Core 第11.3.2節・第1.1.10節: 既定帳票が空ならカタログ先頭で埋めない'
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void getActiveTemplates_returnsActiveRowsWithoutDefaultCountGate() {
    List<ContractDocumentTemplateService.TemplateDefinition> estimateRows =
      ContractDocumentTemplateService.getActiveTemplates(
        ContractDocumentTemplateService.TYPE_ESTIMATE
      );
    System.assertEquals(
      false,
      estimateRows.isEmpty(),
      'Core 第11.3.2節: 有効な帳票行を出す'
    );
  }

  @IsTest
  static void catalog_hasIsDefaultField() {
    System.assertEquals(
      true,
      ContractDocumentTemplate__mdt.SObjectType.getDescribe()
        .fields.getMap()
        .containsKey('IsDefault__c'),
      'Core 第11.3.2節: 既定はカタログ IsDefault'
    );
  }

  @IsTest
  static void initialSelectionKey_bundledRowIsExactlyOneDefault() {
    System.assertEquals(
      ContractDocumentTemplateService.DEFAULT_ESTIMATE_KEY,
      ContractDocumentTemplateService.initialSelectionKey(
        ContractDocumentTemplateService.TYPE_ESTIMATE
      ),
      'Core 第11.3.2節: 同梱は有効な既定ちょうど1つ'
    );
    System.assertEquals(
      ContractDocumentTemplateService.DEFAULT_INVOICE_KEY,
      ContractDocumentTemplateService.initialSelectionKey(
        ContractDocumentTemplateService.TYPE_INVOICE
      )
    );
  }

  @IsTest
  static void initialSelectionKey_zeroOrManyDefaults_returnsNull() {
    ContractDocumentTemplateService.testRecords = new List<ContractDocumentTemplate__mdt>{
      templateRow('A', false),
      templateRow('B', false)
    };
    System.assertEquals(
      null,
      ContractDocumentTemplateService.initialSelectionKey(
        ContractDocumentTemplateService.TYPE_ESTIMATE
      ),
      'Core 第11.3.2節: 有効な既定0件なら未選択'
    );

    ContractDocumentTemplateService.testRecords = new List<ContractDocumentTemplate__mdt>{
      templateRow('A', true),
      templateRow('B', true)
    };
    System.assertEquals(
      null,
      ContractDocumentTemplateService.initialSelectionKey(
        ContractDocumentTemplateService.TYPE_ESTIMATE
      ),
      'Core 第11.3.2節: 有効な既定2件以上なら未選択'
    );
    ContractDocumentTemplateService.clearTestState();
  }

  private static ContractDocumentTemplate__mdt templateRow(
    String key,
    Boolean isDefault
  ) {
    return new ContractDocumentTemplate__mdt(
      MasterLabel = key,
      TemplateKey__c = key,
      DocumentType__c = ContractDocumentTemplateService.TYPE_ESTIMATE,
      IsActive__c = true,
      IsDefault__c = isDefault,
      VisualforcePage__c = 'EstimateDocumentPdf',
      SortOrder__c = 1
    );
  }

  @IsTest
  static void buildPageReferenceUsesConfiguredPageAndTemplateKey() {
    ContractDocumentTemplateService.TemplateDefinition estimate = ContractDocumentTemplateService.resolveTemplate(
      ContractDocumentTemplateService.TYPE_ESTIMATE,
      ContractDocumentTemplateService.DEFAULT_ESTIMATE_KEY
    );

    PageReference pageReference = ContractDocumentTemplateService.buildPageReference(
      estimate,
      UserInfo.getUserId()
    );

    System.assert(pageReference.getUrl().startsWith('/apex/EstimateDocumentPdf'));
    System.assertEquals(
      String.valueOf(UserInfo.getUserId()),
      pageReference.getParameters().get('id')
    );
    System.assertEquals(
      ContractDocumentTemplateService.DEFAULT_ESTIMATE_KEY,
      pageReference.getParameters().get('templateKey')
    );
  }

  @IsTest
  static void invalidDocumentTypeIsRejected() {
    Boolean thrown = false;
    try {
      ContractDocumentTemplateService.getActiveTemplates('Other');
    } catch (
      ContractDocumentTemplateService.DocumentTemplateException ex
    ) {
      thrown = true;
      System.assert(ex.getMessage().contains('帳票種別が不正'));
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void resolveTemplate_rejectsUnknownKeyAndTrimsKnownKey() {
    Boolean thrown = false;
    try {
      ContractDocumentTemplateService.resolveTemplate(
        ContractDocumentTemplateService.TYPE_ESTIMATE,
        'NoSuchTemplate'
      );
    } catch (
      ContractDocumentTemplateService.DocumentTemplateException ex
    ) {
      thrown = true;
      System.assert(
        ex.getMessage().contains('指定された帳票テンプレートは存在しないか無効です'),
        'Core 第11.3.2節: 無効行と無いキーは出さない'
      );
    }
    System.assertEquals(true, thrown);
    ContractDocumentTemplateService.TemplateDefinition trimmed = ContractDocumentTemplateService.resolveTemplate(
      ContractDocumentTemplateService.TYPE_ESTIMATE,
      '  ' + ContractDocumentTemplateService.DEFAULT_ESTIMATE_KEY + '  '
    );
    System.assertEquals(
      ContractDocumentTemplateService.DEFAULT_ESTIMATE_KEY,
      trimmed.templateKey
    );
  }

  @IsTest
  static void buildPageReference_rejectsNullAndInvalidPage() {
    Boolean nullThrown = false;
    try {
      ContractDocumentTemplateService.buildPageReference(null, null);
    } catch (
      ContractDocumentTemplateService.DocumentTemplateException ex
    ) {
      nullThrown = true;
      System.assert(
        ex.getMessage().contains('帳票テンプレートが指定されていません'),
        'Core 第11.3.2節: 帳票はカタログ行の VF を指す'
      );
    }
    System.assertEquals(true, nullThrown);

    ContractDocumentTemplateService.TemplateDefinition estimate = ContractDocumentTemplateService.resolveTemplate(
      ContractDocumentTemplateService.TYPE_ESTIMATE,
      ContractDocumentTemplateService.DEFAULT_ESTIMATE_KEY
    );
    estimate.visualforcePage = 'bad-page';
    Boolean pageThrown = false;
    try {
      ContractDocumentTemplateService.buildPageReference(estimate, null);
    } catch (
      ContractDocumentTemplateService.DocumentTemplateException ex
    ) {
      pageThrown = true;
      System.assert(
        ex.getMessage().contains('Visualforceページ名が不正です'),
        'Core 第11.3.2節: カタログは VF の API 名を指す'
      );
    }
    System.assertEquals(true, pageThrown);
  }
}
