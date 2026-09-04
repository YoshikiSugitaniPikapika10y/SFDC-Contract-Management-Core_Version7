/**
 * 見積・請求の送付メールカタログを解決する。
 * 公開フォルダの Classic メールテンプレートは全件拾わない。
 */
public without sharing class ContractEmailTemplateService {
  public static final String TYPE_ESTIMATE = 'Estimate';
  public static final String TYPE_INVOICE = 'Invoice';
  public static final String TEMPLATE_TYPE_TEXT = 'text';
  public static final String MISSING_CATALOG_MESSAGE =
    'PDFとメール送付のとき、その種別の送付メールカタログに有効行が1件以上必要です。';
  public static final String MISSING_DEFAULT_EMAIL_MESSAGE =
    'PDFとメール送付のとき、既定メールをカタログから選んでください。';
  public static final String DUPLICATE_API_NAME_MESSAGE =
    '同じ種別の有効な送付メールカタログ行が同じAPI名を複数持っています。';
  public static final String NOT_IN_CATALOG_MESSAGE =
    '指定された送付メールは、その種別の有効カタログにありません。';
  public static final String INVALID_SALESFORCE_TEMPLATE_MESSAGE =
    '送付メールはテキスト形式のClassicで、有効かつ公開のメールフォルダにある必要があります。HTML、カスタムHTML、Visualforce、Lightningビルダーは使えません。';
  public static final String MISSING_API_NAME_MESSAGE =
    '送付メールテンプレートが指定されていません。';

  @TestVisible
  static List<ContractEmailTemplate__mdt> testRecords;
  @TestVisible
  static Boolean skipSalesforceTemplateLookup = false;

  public class EmailTemplateException extends Exception {
  }

  public class EmailTemplateDefinition {
    @AuraEnabled
    public String apiName;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Decimal sortOrder;
    @AuraEnabled
    public Boolean isDefault;
    public Id emailTemplateId;
  }

  /** 仕様: Core 第11.3.2節 */
  public static List<EmailTemplateDefinition> getActiveTemplates(
    String documentType
  ) {
    assertDocumentType(documentType);
    List<ContractEmailTemplate__mdt> records = loadRecords(documentType);
    Map<String, Integer> apiNameCounts = new Map<String, Integer>();
    List<EmailTemplateDefinition> definitions = new List<EmailTemplateDefinition>();
    for (ContractEmailTemplate__mdt record : records) {
      if (String.isBlank(record.EmailTemplateApiName__c)) {
        throw new EmailTemplateException(
          record.MasterLabel + ' のメールテンプレートAPI名が空です。'
        );
      }
      String apiName = record.EmailTemplateApiName__c.trim();
      Integer count = apiNameCounts.containsKey(apiName)
        ? apiNameCounts.get(apiName)
        : 0;
      apiNameCounts.put(apiName, count + 1);
      EmailTemplateDefinition definition = new EmailTemplateDefinition();
      definition.apiName = apiName;
      definition.label = record.MasterLabel;
      definition.sortOrder = record.SortOrder__c;
      definition.isDefault = record.IsDefault__c == true;
      definitions.add(definition);
    }
    for (Integer count : apiNameCounts.values()) {
      if (count > 1) {
        throw new EmailTemplateException(DUPLICATE_API_NAME_MESSAGE);
      }
    }
    return definitions;
  }

  /**
   * 仕様: Core 第11.3.2節。有効かつ既定がちょうど1つならその API 名。
   * 0件または2件以上なら null。発行・送付 Apex の空埋めには使わない。
   */
  public static String initialSelectionApiName(String documentType) {
    String found = null;
    Integer defaults = 0;
    for (EmailTemplateDefinition definition : getActiveTemplates(documentType)) {
      if (definition.isDefault == true) {
        defaults++;
        found = definition.apiName;
      }
    }
    return defaults == 1 ? found : null;
  }

  /** 仕様: Core 第11.3.2節、第7.10節 */
  public static EmailTemplateDefinition resolveTemplate(
    String documentType,
    String apiName
  ) {
    if (String.isBlank(apiName)) {
      throw new EmailTemplateException(MISSING_API_NAME_MESSAGE);
    }
    String trimmed = apiName.trim();
    EmailTemplateDefinition matched;
    for (EmailTemplateDefinition definition : getActiveTemplates(documentType)) {
      if (definition.apiName == trimmed) {
        matched = definition;
        break;
      }
    }
    if (matched == null) {
      throw new EmailTemplateException(NOT_IN_CATALOG_MESSAGE);
    }
    applySalesforceTemplate(matched);
    return matched;
  }

  /**
   * 仕様: Core 第11.3.2節、第4.8節、第7.10節。
   * 指定が空ならエラー。orgDefaultApiName は使わない（組織設定に既定メールは無い）。
   */
  public static EmailTemplateDefinition resolveForOperation(
    String documentType,
    String requestedApiName,
    String orgDefaultApiName
  ) {
    return resolveTemplate(documentType, requestedApiName);
  }

  public class MergeResult {
    public String apiName;
    public Id emailTemplateId;
    public String subject;
    public String body;
  }

  /** 仕様: Core 第7.10節、第4.8節 */
  public static MergeResult renderForSend(
    String documentType,
    String requestedApiName,
    String orgDefaultApiName,
    Id relatedRecordId
  ) {
    return renderForSend(
      documentType,
      requestedApiName,
      orgDefaultApiName,
      relatedRecordId,
      UserInfo.getUserId()
    );
  }

  /**
   * 仕様: Core 第7.10節。whoId は見積送付先 Contact、無ければ操作者 User。
   * 操作者 User の項目で {!Contact.～} を埋めない。
   */
  public static MergeResult renderForSend(
    String documentType,
    String requestedApiName,
    String orgDefaultApiName,
    Id relatedRecordId,
    Id whoId
  ) {
    EmailTemplateDefinition definition = resolveForOperation(
      documentType,
      requestedApiName,
      orgDefaultApiName
    );
    MergeResult result = new MergeResult();
    result.apiName = definition.apiName;
    result.emailTemplateId = definition.emailTemplateId;
    if (skipSalesforceTemplateLookup == true || Test.isRunningTest()) {
      result.subject = '';
      result.body = '';
      return result;
    }
    Id mergeWhoId = whoId == null ? UserInfo.getUserId() : whoId;
    Messaging.SingleEmailMessage rendered = Messaging.renderStoredEmailTemplate(
      definition.emailTemplateId,
      mergeWhoId,
      relatedRecordId
    );
    result.subject = rendered.getSubject();
    result.body = rendered.getPlainTextBody();
    return result;
  }

  public class OrgWideResolved {
    public Id orgWideId;
    public String address;
    public String displayName;
  }

  /** 仕様: Core 第11.3.2節、第7.10節 */
  public static OrgWideResolved resolveOrgWide(String savedAddress) {
    if (String.isBlank(savedAddress)) {
      throw new EmailTemplateException(
        ContractDocumentSettingService.MISSING_ORG_SENDER_MESSAGE
      );
    }
    String trimmed = savedAddress.trim();
    List<OrgWideEmailAddress> rows = [
      SELECT Id, Address, DisplayName
      FROM OrgWideEmailAddress
      WHERE Address = :trimmed AND IsVerified = true
      WITH SYSTEM_MODE
    ];
    if (rows.isEmpty()) {
      throw new EmailTemplateException(
        ContractDocumentSettingService.ORG_SENDER_NOT_FOUND_MESSAGE
      );
    }
    if (rows.size() > 1) {
      throw new EmailTemplateException(
        ContractDocumentSettingService.ORG_SENDER_AMBIGUOUS_MESSAGE
      );
    }
    OrgWideResolved resolved = new OrgWideResolved();
    resolved.orgWideId = rows[0].Id;
    resolved.address = rows[0].Address;
    resolved.displayName = rows[0].DisplayName;
    return resolved;
  }

  /** 仕様: Core 第7.10節。Fromは組織送信元の参照。表示名は保存しない。 */
  public static String formatOrgWideFrom(OrgWideResolved resolved) {
    if (resolved == null || String.isBlank(resolved.address)) {
      return '';
    }
    if (String.isBlank(resolved.displayName)) {
      return resolved.address;
    }
    return resolved.displayName + ' <' + resolved.address + '>';
  }

  @TestVisible
  static void seedActiveRowForTest(String documentType, String apiName) {
    if (testRecords == null) {
      testRecords = new List<ContractEmailTemplate__mdt>();
    }
    ContractEmailTemplate__mdt row = new ContractEmailTemplate__mdt();
    row.MasterLabel = apiName;
    row.DocumentType__c = documentType;
    row.EmailTemplateApiName__c = apiName;
    row.IsActive__c = true;
    row.IsDefault__c = false;
    row.SortOrder__c = 1;
    testRecords.add(row);
    skipSalesforceTemplateLookup = true;
  }

  @TestVisible
  static void clearTestState() {
    testRecords = null;
    skipSalesforceTemplateLookup = false;
  }

  private static void applySalesforceTemplate(EmailTemplateDefinition definition) {
    if (skipSalesforceTemplateLookup == true) {
      return;
    }
    List<EmailTemplate> templates = [
      SELECT
        Id,
        Name,
        DeveloperName,
        TemplateType,
        IsActive,
        IsBuilderContent,
        Folder.AccessType,
        Folder.Type
      FROM EmailTemplate
      WHERE DeveloperName = :definition.apiName
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (templates.isEmpty()) {
      throw new EmailTemplateException(INVALID_SALESFORCE_TEMPLATE_MESSAGE);
    }
    EmailTemplate record = templates[0];
    Boolean publicEmailFolder =
      record.Folder != null &&
      record.Folder.AccessType == 'Public' &&
      record.Folder.Type == 'Email';
    if (
      record.TemplateType != TEMPLATE_TYPE_TEXT ||
      record.IsActive != true ||
      record.IsBuilderContent == true ||
      !publicEmailFolder
    ) {
      throw new EmailTemplateException(INVALID_SALESFORCE_TEMPLATE_MESSAGE);
    }
    definition.emailTemplateId = record.Id;
    if (String.isNotBlank(record.Name)) {
      definition.label = record.Name;
    }
  }

  private static List<ContractEmailTemplate__mdt> loadRecords(String documentType) {
    if (testRecords != null) {
      List<ContractEmailTemplate__mdt> filtered = new List<ContractEmailTemplate__mdt>();
      for (ContractEmailTemplate__mdt record : testRecords) {
        if (record.DocumentType__c == documentType && record.IsActive__c == true) {
          filtered.add(record);
        }
      }
      return filtered;
    }
    return [
      SELECT
        MasterLabel,
        DocumentType__c,
        EmailTemplateApiName__c,
        IsActive__c,
        IsDefault__c,
        SortOrder__c
      FROM ContractEmailTemplate__mdt
      WHERE DocumentType__c = :documentType AND IsActive__c = TRUE
      ORDER BY SortOrder__c ASC NULLS LAST, MasterLabel ASC
    ];
  }

  private static void assertDocumentType(String documentType) {
    if (documentType != TYPE_ESTIMATE && documentType != TYPE_INVOICE) {
      throw new EmailTemplateException('帳票種別が不正です: ' + documentType);
    }
  }

}
