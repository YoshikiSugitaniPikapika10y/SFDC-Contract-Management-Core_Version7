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
  static void catalog_doesNotHaveIsDefaultField() {
    System.assertEquals(
      false,
      ContractDocumentTemplate__mdt.SObjectType.getDescribe()
        .fields.getMap()
        .containsKey('IsDefault__c'),
      'Core 第11.3.2節: 既定は組織設定のキー。CMDT IsDefault は持たない'
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
}
