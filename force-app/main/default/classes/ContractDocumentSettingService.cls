/**
 * 組織1件の帳票・送付・見積有効月数・既定サイクル数・更新商談スイッチを読む。
 */
public without sharing class ContractDocumentSettingService {
  public static final String MODE_UNUSED = 'Unused';
  public static final String MODE_PDF_ONLY = 'PdfOnly';
  public static final String MODE_PDF_AND_EMAIL = 'PdfAndEmail';
  public static final String MISSING_SETTING_MESSAGE = '契約帳票・送付設定の組織既定がありません。';
  public static final String INVALID_SEND_MODE_MESSAGE = '見積書・請求書の3択が無い、空、または不正です。';
  public static final String INVALID_ESTIMATE_VALID_MONTHS_MESSAGE =
    '見積有効期間は1～12の整数で設定してください。';
  public static final String INVALID_DEFAULT_CYCLES_MESSAGE =
    '既定サイクル数は1～36の整数で設定してください。';
  public static final String MISSING_COMPANY_NAME_MESSAGE = '会社名を設定してください。';
  public static final String MISSING_ADDRESS_MESSAGE = '住所を設定してください。';
  public static final String MISSING_REGISTRATION_NUMBER_MESSAGE =
    '適格請求書発行事業者登録番号を設定してください。';
  public static final String MISSING_BANK_TRANSFER_MESSAGE = '振込先を設定してください。';
  public static final String MISSING_DEFAULT_DOCUMENT_MESSAGE =
    'PDFのみ／PDFとメール送付のとき、既定帳票を選んでください。';
  public static final String MISSING_ORG_SENDER_MESSAGE =
    'PDFとメール送付のとき、組織の送信元を選んでください。';
  public static final String ORG_SENDER_NOT_FOUND_MESSAGE =
    '保存した組織送信元アドレスに一致する検証済みの組織ワイドメールがありません。';
  public static final String ORG_SENDER_AMBIGUOUS_MESSAGE =
    '保存した組織送信元アドレスに一致する検証済みの組織ワイドメールが複数あります。';
  public static final String DOCUMENT_SEND_HEADING = '帳票・送付';

  private static ContractDocumentSetting__c cachedOrgSetting;

  /** 仕様: Core 第7.10節、第11.3.1節、第11.6節。発行・送付・確定の不足エラーに見出し名を付ける。 */
  public static String withDocumentSendHeading(String body) {
    if (String.isBlank(body)) {
      return body;
    }
    if (body.startsWith(DOCUMENT_SEND_HEADING)) {
      return body;
    }
    return DOCUMENT_SEND_HEADING + '：' + body;
  }

  /** 仕様: Core 第11.3節、第4.10節、第1.1.10節 */
  public static String requireSendMode(String documentKind) {
    ContractDocumentSetting__c setting = requireOrgSetting();
    String mode;
    if (documentKind == 'Estimate') {
      mode = setting.EstimateSendMode__c;
    } else if (documentKind == 'Invoice') {
      mode = setting.InvoiceSendMode__c;
    } else {
      throw new SettingException('見積書または請求書を指定してください。');
    }
    if (
      mode != MODE_UNUSED &&
      mode != MODE_PDF_ONLY &&
      mode != MODE_PDF_AND_EMAIL
    ) {
      throw new SettingException(INVALID_SEND_MODE_MESSAGE);
    }
    return mode;
  }

  /** 仕様: Core 第4.10節、日付仕様 第2.6節 */
  public static Integer requireEstimateValidMonths() {
    ContractDocumentSetting__c setting = requireOrgSetting();
    Decimal raw = setting.EstimateValidMonths__c;
    if (raw == null || raw != raw.intValue() || raw < 1 || raw > 12) {
      throw new SettingException(INVALID_ESTIMATE_VALID_MONTHS_MESSAGE);
    }
    return raw.intValue();
  }

  /** 仕様: 日付仕様 第2.5節 */
  public static Integer requireDefaultCycles() {
    ContractDocumentSetting__c setting = requireOrgSetting();
    Decimal raw = setting.DefaultMonthlyCycles__c;
    if (raw == null || raw != raw.intValue() || raw < 1 || raw > 36) {
      throw new SettingException(INVALID_DEFAULT_CYCLES_MESSAGE);
    }
    return raw.intValue();
  }

  /** 仕様: Core 第11.5節 */
  public static Boolean requireRenewOpportunitySwitch() {
    return requireOrgSetting().RenewOpportunityEnabled__c == true;
  }

  /** 仕様: Core 第11.3.1節、第4.8節、第7.10節 */
  public static void assertRequiredCompanyFields() {
    assertRequiredCompanyFields(requireOrgSetting());
  }

  /** 仕様: Core 第11.3.1節 */
  public static void assertRequiredCompanyFields(
    ContractDocumentSetting__c setting
  ) {
    if (setting == null) {
      throw new SettingException(MISSING_SETTING_MESSAGE);
    }
    Boolean estimateUsed = isUsed(setting.EstimateSendMode__c);
    Boolean invoiceUsed = isUsed(setting.InvoiceSendMode__c);
    if (estimateUsed || invoiceUsed) {
      if (String.isBlank(setting.CompanyName__c)) {
        throw new SettingException(MISSING_COMPANY_NAME_MESSAGE);
      }
      if (String.isBlank(setting.Address__c)) {
        throw new SettingException(MISSING_ADDRESS_MESSAGE);
      }
    }
    if (invoiceUsed) {
      if (String.isBlank(setting.InvoiceRegistrationNumber__c)) {
        throw new SettingException(MISSING_REGISTRATION_NUMBER_MESSAGE);
      }
      if (String.isBlank(setting.BankTransferInfo__c)) {
        throw new SettingException(MISSING_BANK_TRANSFER_MESSAGE);
      }
    }
  }

  /** 仕様: Core 第11.3.2節、第11.6節。既定帳票・既定メールは組織設定に無い。 */
  public static void assertModeCatalogRequirements(
    String mode,
    Integer catalogSize,
    String orgWideEmailAddress
  ) {
    assertModeCatalogRequirements(
      mode,
      catalogSize,
      orgWideEmailAddress,
      true
    );
  }

  /**
   * 仕様: Core 第11.3.2節。
   * PDFとメール送付のとき、請求用組織送信元は必須。見積用は空でよい。
   * 既定キー必須では保存を止めない。
   */
  public static void assertModeCatalogRequirements(
    String mode,
    Integer catalogSize,
    String orgWideEmailAddress,
    Boolean requireOrgWideSender
  ) {
    if (mode == MODE_UNUSED) {
      return;
    }
    if (mode != MODE_PDF_ONLY && mode != MODE_PDF_AND_EMAIL) {
      throw new SettingException(INVALID_SEND_MODE_MESSAGE);
    }
    if (mode == MODE_PDF_AND_EMAIL) {
      if (catalogSize == null || catalogSize < 1) {
        throw new SettingException(
          ContractEmailTemplateService.MISSING_CATALOG_MESSAGE
        );
      }
      if (
        requireOrgWideSender == true &&
        String.isBlank(orgWideEmailAddress)
      ) {
        throw new SettingException(MISSING_ORG_SENDER_MESSAGE);
      }
    }
  }

  private static Boolean isUsed(String mode) {
    return mode != MODE_UNUSED && String.isNotBlank(mode);
  }

  /** 仕様: Core 第11.6節。製品は組織既定だけを読む。ユーザー／プロファイル行は見ない。 */
  public static ContractDocumentSetting__c requireOrgSetting() {
    if (cachedOrgSetting != null) {
      return cachedOrgSetting;
    }
    Id organizationId = UserInfo.getOrganizationId();
    List<ContractDocumentSetting__c> settings = [
      SELECT
        Id,
        EstimateSendMode__c,
        InvoiceSendMode__c,
        EstimateValidMonths__c,
        DefaultMonthlyCycles__c,
        RenewOpportunityEnabled__c,
        CompanyName__c,
        Address__c,
        InvoiceRegistrationNumber__c,
        BankTransferInfo__c,
        EstimateOrgWideEmailAddress__c,
        InvoiceOrgWideEmailAddress__c
      FROM ContractDocumentSetting__c
      WHERE SetupOwnerId = :organizationId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (settings.isEmpty()) {
      throw new SettingException(MISSING_SETTING_MESSAGE);
    }
    cachedOrgSetting = settings[0];
    return cachedOrgSetting;
  }

  @TestVisible
  static void clearCache() {
    cachedOrgSetting = null;
  }

  public class SettingException extends Exception {
  }
}
