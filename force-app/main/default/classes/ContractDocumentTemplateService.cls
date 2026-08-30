/**
 * 見積書・請求書で共用する帳票テンプレート定義を解決する。
 * 帳票の入口は CMDT に登録された Visualforce ページとし、
 * Apex クラス名は動的に扱わない。
 */
public without sharing class ContractDocumentTemplateService {
  public static final String TYPE_ESTIMATE = 'Estimate';
  public static final String TYPE_INVOICE = 'Invoice';
  public static final String DEFAULT_ESTIMATE_KEY = 'StandardEstimate';
  public static final String DEFAULT_INVOICE_KEY = 'StandardInvoice';

  public class DocumentTemplateException extends Exception {
  }

  public class TemplateDefinition {
    @AuraEnabled
    public String templateKey;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String documentType;
    @AuraEnabled
    public String visualforcePage;
    @AuraEnabled
    public String fileNamePattern;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public Decimal sortOrder;

    private TemplateDefinition(ContractDocumentTemplate__mdt record) {
      templateKey = record.TemplateKey__c;
      label = record.MasterLabel;
      documentType = record.DocumentType__c;
      visualforcePage = record.VisualforcePage__c;
      fileNamePattern = record.FileNamePattern__c;
      description = record.Description__c;
      sortOrder = record.SortOrder__c;
    }
  }

  /** 仕様: Core 第11.3.2節。有効行を出す。既定は組織設定のキー。 */
  public static List<TemplateDefinition> getActiveTemplates(
    String documentType
  ) {
    assertDocumentType(documentType);
    List<ContractDocumentTemplate__mdt> records = [
      SELECT
        MasterLabel,
        DocumentType__c,
        TemplateKey__c,
        IsActive__c,
        SortOrder__c,
        VisualforcePage__c,
        FileNamePattern__c,
        Description__c
      FROM ContractDocumentTemplate__mdt
      WHERE DocumentType__c = :documentType AND IsActive__c = TRUE
      ORDER BY SortOrder__c ASC NULLS LAST, MasterLabel ASC
    ];

    List<TemplateDefinition> definitions = new List<TemplateDefinition>();
    for (ContractDocumentTemplate__mdt record : records) {
      validateRecord(record);
      definitions.add(new TemplateDefinition(record));
    }
    return definitions;
  }

  public static TemplateDefinition resolveTemplate(
    String documentType,
    String templateKey
  ) {
    List<TemplateDefinition> definitions = getActiveTemplates(documentType);
    if (definitions.isEmpty()) {
      throw new DocumentTemplateException(
        documentType + ' の有効な帳票テンプレートがありません。'
      );
    }

    if (String.isBlank(templateKey)) {
      throw new DocumentTemplateException(
        ContractDocumentSettingService.MISSING_DEFAULT_DOCUMENT_MESSAGE
      );
    }
    for (TemplateDefinition definition : definitions) {
      if (definition.templateKey == templateKey.trim()) {
        return definition;
      }
    }
    throw new DocumentTemplateException(
      '指定された帳票テンプレートは存在しないか無効です: ' + templateKey
    );
  }

  public static PageReference buildPageReference(
    TemplateDefinition definition,
    Id recordId
  ) {
    if (definition == null) {
      throw new DocumentTemplateException('帳票テンプレートが指定されていません。');
    }
    if (
      String.isBlank(definition.visualforcePage) ||
      !Pattern.matches(
        '^[A-Za-z][A-Za-z0-9_]*$',
        definition.visualforcePage
      )
    ) {
      throw new DocumentTemplateException(
        'Visualforceページ名が不正です: ' + definition.visualforcePage
      );
    }
    PageReference pageReference = new PageReference(
      '/apex/' + definition.visualforcePage
    );
    if (recordId != null) {
      pageReference.getParameters().put('id', String.valueOf(recordId));
    }
    pageReference.getParameters().put('templateKey', definition.templateKey);
    return pageReference;
  }

  private static void assertDocumentType(String documentType) {
    if (documentType != TYPE_ESTIMATE && documentType != TYPE_INVOICE) {
      throw new DocumentTemplateException(
        '帳票種別が不正です: ' + documentType
      );
    }
  }

  private static void validateRecord(ContractDocumentTemplate__mdt record) {
    if (String.isBlank(record.TemplateKey__c)) {
      throw new DocumentTemplateException(
        record.MasterLabel + ' のテンプレートキーが空です。'
      );
    }
    if (
      String.isBlank(record.VisualforcePage__c) ||
      !Pattern.matches('^[A-Za-z][A-Za-z0-9_]*$', record.VisualforcePage__c)
    ) {
      throw new DocumentTemplateException(
        record.MasterLabel + ' のVisualforceページ名が不正です。'
      );
    }
  }
}
