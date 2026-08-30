@IsTest
private class ContractEmailTemplateServiceTest {
  @IsTest
  static void getActiveTemplates_emptyCatalog_returnsEmpty() {
    ContractEmailTemplateService.clearTestState();
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
}
