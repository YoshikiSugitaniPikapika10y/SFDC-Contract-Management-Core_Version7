/**
 * 見積作成 LWC（estimateCreate*）向け Apex コントローラ（薄いファサード）。
 * DTO と @AuraEnabled 入口のみを保持し、実処理は Query/Save/Validation/Support へ委譲する。
 *
 * Change の課金イベント判定は ChangeBillingEventUtil / LWC estimateLineItemUtils と
 * 定義を揃えること（実装をむやみに片方だけ変えない）。
 */
public without sharing class EstimateCreateController {
  public class ProductDefaultDto {
    @AuraEnabled
    public String unitName;

    @AuraEnabled
    public Decimal unitPrice;

    @AuraEnabled
    public String invoiceType;

    @AuraEnabled
    public String billingType;

    @AuraEnabled
    public String billingCycle;

    @AuraEnabled
    public String revenueRecognitionBasis;

    @AuraEnabled
    public String displayUnit;

    @AuraEnabled
    public String productName;

    @AuraEnabled
    public Map<String, String> productVisibilityContext;
  }

  public class ProductLineItem {
    @AuraEnabled
    public Id productId;

    @AuraEnabled
    public String productName;

    @AuraEnabled
    public Decimal quantity;

    @AuraEnabled
    public Decimal unitPrice;

    @AuraEnabled
    public Decimal amount;

    @AuraEnabled
    public String startDate;

    @AuraEnabled
    public String endDate;

    @AuraEnabled
    public String invoiceType;

    @AuraEnabled
    public String unit;

    /** Product2.UnitName__c。表示用。永続 Unit__c とは別。 */
    @AuraEnabled
    public String unitName;

    @AuraEnabled
    public String billingType;

    @AuraEnabled
    public String billingCycle;

    @AuraEnabled
    public String revenueRecognitionBasis;

    @AuraEnabled
    public String recordType;

    @AuraEnabled
    public String typeLabel;

    @AuraEnabled
    public Boolean isDuplicate;

    @AuraEnabled
    public Id sourceContractProductId;

    @AuraEnabled
    public Id contractProductId;

    @AuraEnabled
    public Boolean isReadonly;

    @AuraEnabled
    public String pairId;

    @AuraEnabled
    public Map<String, Object> customFields;

    @AuraEnabled
    public Map<String, String> productVisibilityContext;
  }

  public class EstimateCopyPresetDto {
    @AuraEnabled
    public Id opportunityId;

    @AuraEnabled
    public String opportunityName;

    @AuraEnabled
    public String accountName;

    @AuraEnabled
    public String selectedType;

    @AuraEnabled
    public String contractServiceName;

    @AuraEnabled
    public String contractHistoryName;

    @AuraEnabled
    public Id contractServiceId;

    @AuraEnabled
    public Id contractHistoryId;

    @AuraEnabled
    public String contractStartDate;

    /** @deprecated LWC は contractEndDate を正とする。互換のため残す。 */
    @AuraEnabled
    public String endDate;

    @AuraEnabled
    public String contractEndDate;

    @AuraEnabled
    public String contractEffectiveDate;

    @AuraEnabled
    public String autoHistoryName;

    @AuraEnabled
    public Decimal baseHistoryVersion;

    @AuraEnabled
    public Decimal nextHistoryVersion;

    @AuraEnabled
    public String previousTermStartDate;

    @AuraEnabled
    public String previousTermEndDate;

    @AuraEnabled
    public Boolean renewEligible;

    /** Term / Spot。New コピー（サービス新規化）では空 */
    @AuraEnabled
    public String serviceLifecycle;

    @AuraEnabled
    public List<ProductLineItem> selectedProducts;

    @AuraEnabled
    public Id estimateRemarkMasterId;

    @AuraEnabled
    public String estimateRemarks;

    @AuraEnabled
    public Id billingAccountId;

    @AuraEnabled
    public Boolean contractCustomFieldsExpanded;

    @AuraEnabled
    public Map<String, Object> contractServiceCustomFields;

    @AuraEnabled
    public Map<String, Object> contractHistoryCustomFields;

    @AuraEnabled
    public String historyStatus;

    /** 同時編集ガード用。ContractHistory.LastModifiedDate の epoch ms 文字列 */
    @AuraEnabled
    public String lastModifiedToken;

    /** 表示％。New の編集／コピーで保存済み税率を戻す */
    @AuraEnabled
    public Decimal taxPercent;

    @AuraEnabled
    public String estimateDate;

    @AuraEnabled
    public String estimateValidDate;

    /** 仕様: Core 第4.3.3節。見積送付先。Ordered編集では画面に出さない。 */
    @AuraEnabled
    public Id estimateSendContactId;
  }

  public class BillingAccountInvoiceSettingsDto {
    @AuraEnabled
    public Integer billingDayOfMonth;

    @AuraEnabled
    public String billingDayOfMonthPicklistValue;

    @AuraEnabled
    public String billingDayOfMonthLabel;

    @AuraEnabled
    public String paymentTerm;

    @AuraEnabled
    public Boolean adjustInvoiceDateToBusinessDay;

    /** 仕様: Core 第5.2節 */
    @AuraEnabled
    public Map<String, Object> billingCustomFields;
  }

  public class BillingAccountOptionDto {
    @AuraEnabled
    public Id id;

    @AuraEnabled
    public String name;
  }

  public class ContractServiceOptionDto {
    @AuraEnabled
    public Id id;

    @AuraEnabled
    public String name;

    /** Term / Spot。未設定は null */
    @AuraEnabled
    public String lifecycle;

    /** 表示用: 期間契約 / 都度契約 */
    @AuraEnabled
    public String lifecycleLabel;

    /** 契約期間状態。数式の日本語値をそのまま載せる */
    @AuraEnabled
    public String status;

    /** 表示用。status と同じ日本語値 */
    @AuraEnabled
    public String statusLabel;

    /** 継続課金の契約開始日（期間契約） */
    @AuraEnabled
    public Date termStart;

    /** 継続課金の契約終了日（期間契約） */
    @AuraEnabled
    public Date termEnd;

    /** 更新残月（期間契約。超過はマイナス） */
    @AuraEnabled
    public Decimal renewalRemainingMonths;

    /** 最新 Ordered の契約履歴名 */
    @AuraEnabled
    public String historyName;

    /** 最新 Ordered の Version */
    @AuraEnabled
    public Decimal version;

    /** 最新 Ordered の請求アカウント */
    @AuraEnabled
    public Id billingAccountId;

    /** 最新 Ordered の請求アカウント名（選択肢表示用） */
    @AuraEnabled
    public String billingAccountName;

    /**
     * 期間契約のみ: 現契約期間と重なる継続課金商品名（重複除く、カンマ区切り）。
     * Spot は null。
     */
    @AuraEnabled
    public String currentProductNames;

    /** 表示％。未設定は null */
    @AuraEnabled
    public Decimal taxPercent;
  }

  public class EstimateSaveRequest {
    @AuraEnabled
    public Id opportunityId;

    @AuraEnabled
    public String selectedType;

    @AuraEnabled
    public String contractServiceName;

    @AuraEnabled
    public Id contractServiceId;

    @AuraEnabled
    public Id previousHistoryId;

    @AuraEnabled
    public String contractStartDate;

    @AuraEnabled
    public String contractEndDate;

    @AuraEnabled
    public String effectiveDate;

    @AuraEnabled
    public Decimal taxPercent;

    @AuraEnabled
    public String estimateDate;

    @AuraEnabled
    public String estimateValidDate;

    /** 仕様: Core 第4.3.3節。契約履歴へ保存する。必須にしない。 */
    @AuraEnabled
    public Id estimateSendContactId;

    @AuraEnabled
    public String applicationDate;

    @AuraEnabled
    public List<ProductLineItem> products;

    @AuraEnabled
    public Id estimateRemarkMasterId;

    @AuraEnabled
    public String remarksText;

    @AuraEnabled
    public Id billingAccountId;

    @AuraEnabled
    public Id copyFromHistoryId;

    @AuraEnabled
    public Id editHistoryId;

    /** 編集保存時の楽観ロック。preset.lastModifiedToken をそのまま返す */
    @AuraEnabled
    public String expectedLastModifiedToken;

    /** 仕様: Core 第4.3.12節 */
    @AuraEnabled
    public String businessOperationKey;

    public Map<String, Object> contractServiceCustomFields;

    public Map<String, Object> contractHistoryCustomFields;

    /** Aura 引数経由で渡す履歴名（DTO 外だが保存に必要） */
    public String contractHistoryName;
  }

  public class EstimateSaveResult {
    @AuraEnabled
    public Id contractServiceId;

    @AuraEnabled
    public Id contractHistoryId;

    @AuraEnabled
    public List<Id> contractProductIds;

    /** 保存後の楽観ロック用トークン（連続保存用） */
    @AuraEnabled
    public String lastModifiedToken;

    /** 仕様: Core 第4.3.12節 */
    @AuraEnabled
    public String businessOperationKey;
  }

  public class ContractHistoryDto {
    @AuraEnabled
    public Id historyId;

    @AuraEnabled
    public String historyName;

    @AuraEnabled
    public Decimal version;

    @AuraEnabled
    public Decimal nextVersion;

    @AuraEnabled
    public String termStartDate;

    @AuraEnabled
    public String termEndDate;

    @AuraEnabled
    public String historyType;

    @AuraEnabled
    public Boolean renewEligible;

    /** 仕様: Core 第4.3.3節。ベース Ordered の見積送付先。裏コピーではない。 */
    @AuraEnabled
    public Id estimateSendContactId;
  }

  public class ContractProductLineDto {
    @AuraEnabled
    public Id contractProductId;

    @AuraEnabled
    public Id productId;

    @AuraEnabled
    public String productName;

    @AuraEnabled
    public String unitName;

    @AuraEnabled
    public String unit;

    @AuraEnabled
    public Decimal unitPrice;

    @AuraEnabled
    public Decimal quantity;

    /** 契約商品 Amount（金額入力時の保存値含む）。ウィザード復元用。 */
    @AuraEnabled
    public Decimal amount;

    @AuraEnabled
    public String startDate;

    @AuraEnabled
    public String endDate;

    @AuraEnabled
    public String invoiceType;

    @AuraEnabled
    public String billingType;

    @AuraEnabled
    public String billingCycle;

    @AuraEnabled
    public String revenueRecognitionBasis;

    @AuraEnabled
    public Map<String, Object> customFields;

    @AuraEnabled
    public Map<String, String> productVisibilityContext;
  }

  // 見積ウィザードの業務読取はクライアントキャッシュ禁止（開くたび最新）。
  // @wire 利用メソッド（請求先／契約サービス候補／請求設定）のみ cacheable=true を維持。
  @AuraEnabled
  public static List<ContractProductLineDto> getRecurringContractProducts(
    Id contractHistoryId
  ) {
    ContractPermissionUtil.assertEstimateSave(null, null);
    return EstimateQueryService.getRecurringContractProducts(contractHistoryId);
  }

  @AuraEnabled
  public static List<ContractProductLineDto> getRenewContractProducts(
    Id contractServiceId
  ) {
    ContractPermissionUtil.assertEstimateSave(null, null);
    return EstimateQueryService.getRenewContractProducts(contractServiceId);
  }

  @AuraEnabled
  public static ContractHistoryDto getLatestContractHistory(
    Id contractServiceId
  ) {
    ContractPermissionUtil.assertEstimateSave(null, null);
    return EstimateQueryService.getLatestContractHistory(contractServiceId);
  }

  @AuraEnabled
  public static ContractHistoryDto getContractHistoryInfo(
    Id contractHistoryId
  ) {
    ContractPermissionUtil.assertEstimateSave(null, null);
    return EstimateQueryService.getContractHistoryInfo(contractHistoryId);
  }

  @AuraEnabled
  public static EstimateCopyPresetDto getEstimateCopyPreset(
    Id contractHistoryId
  ) {
    ContractPermissionUtil.assertHas(
      ContractPermissionUtil.ESTIMATE,
      '見積コピーを実行する権限がありません。'
    );
    return EstimateQueryService.getEstimateCopyPreset(contractHistoryId);
  }

  @AuraEnabled
  public static EstimateCopyPresetDto getEstimateEditPreset(
    Id contractHistoryId
  ) {
    ContractPermissionUtil.assertHas(
      ContractPermissionUtil.ESTIMATE,
      '見積編集を実行する権限がありません。'
    );
    return EstimateQueryService.getEstimateEditPreset(contractHistoryId);
  }

  /** 仕様: Core 第1.1.10節 */
  @AuraEnabled
  public static ProductDefaultDto getProductDefaults(Id productId) {
    ContractPermissionUtil.assertEstimateSave(null, null);
    return EstimateQueryService.getProductDefaults(productId);
  }

  @AuraEnabled(cacheable=true)
  public static List<ContractMetadataService.InvoiceSettingOption> getInvoiceSettingOptions() {
    ContractPermissionUtil.assertEstimateSave(null, null);
    return EstimateQueryService.getInvoiceSettingOptions();
  }

  @AuraEnabled(cacheable=true)
  public static String getDefaultInvoiceSettingLabel() {
    return EstimateQueryService.getDefaultInvoiceSettingLabel();
  }

  /** 仕様: Core 第1.1.10節、第4.5.2節、第7.6節、Accounting 第3.2節。0件はOFFと埋めない。 */
  @AuraEnabled(cacheable=true)
  public static Boolean isAccountingEnabled() {
    ContractPermissionUtil.assertEstimateSave(null, null);
    return GlAccountingPolicyService.requireOrgPolicy().AccountingEnabled__c ==
      true;
  }

  @AuraEnabled(cacheable=true)
  public static List<BillingAccountOptionDto> getBillingAccountsByAccount(
    Id accountId
  ) {
    return EstimateQueryService.getBillingAccountsByAccount(accountId);
  }

  @AuraEnabled(cacheable=true)
  public static List<ContractServiceOptionDto> getActiveContractServicesByAccount(
    Id accountId
  ) {
    return EstimateQueryService.getActiveContractServicesByAccount(accountId);
  }

  @AuraEnabled(cacheable=true)
  public static BillingAccountInvoiceSettingsDto getBillingAccountInvoiceSettings(
    Id billingAccountId
  ) {
    return EstimateQueryService.getBillingAccountInvoiceSettings(
      billingAccountId
    );
  }

  @AuraEnabled
  public static String getEstimateRemarkMasterText(Id masterId) {
    return EstimateQueryService.getEstimateRemarkMasterText(masterId);
  }

  public static EstimateSaveResult saveEstimate(
    Id opportunityId,
    String selectedType,
    String contractServiceName,
    String contractHistoryName,
    Id contractServiceId,
    Id previousHistoryId,
    String contractStartDate,
    String contractEndDate,
    String effectiveDate,
    String applicationDate,
    String productsJson,
    Id estimateRemarkMasterId,
    String remarksText,
    Id billingAccountId,
    Id copyFromHistoryId
  ) {
    return EstimateSaveService.saveEstimate(
      opportunityId,
      selectedType,
      contractServiceName,
      contractHistoryName,
      contractServiceId,
      previousHistoryId,
      contractStartDate,
      contractEndDate,
      effectiveDate,
      applicationDate,
      productsJson,
      estimateRemarkMasterId,
      remarksText,
      billingAccountId,
      copyFromHistoryId
    );
  }

  public static EstimateSaveResult saveEstimate(
    Id opportunityId,
    String selectedType,
    String contractServiceName,
    String contractHistoryName,
    Id contractServiceId,
    Id previousHistoryId,
    String contractStartDate,
    String contractEndDate,
    String effectiveDate,
    String applicationDate,
    String productsJson,
    Id estimateRemarkMasterId,
    String remarksText,
    Id billingAccountId,
    Id copyFromHistoryId,
    Id editHistoryId
  ) {
    return EstimateSaveService.saveEstimate(
      opportunityId,
      selectedType,
      contractServiceName,
      contractHistoryName,
      contractServiceId,
      previousHistoryId,
      contractStartDate,
      contractEndDate,
      effectiveDate,
      applicationDate,
      productsJson,
      estimateRemarkMasterId,
      remarksText,
      billingAccountId,
      copyFromHistoryId,
      editHistoryId
    );
  }

  /** Apex テスト互換。Aura 公開は expectedLastModifiedToken 付きのみ。 */
  public static EstimateSaveResult saveEstimate(
    Id opportunityId,
    String selectedType,
    String contractServiceName,
    String contractHistoryName,
    Id contractServiceId,
    Id previousHistoryId,
    String contractStartDate,
    String contractEndDate,
    String effectiveDate,
    String applicationDate,
    String productsJson,
    Id estimateRemarkMasterId,
    String remarksText,
    Id billingAccountId,
    Id copyFromHistoryId,
    Id editHistoryId,
    String contractServiceCustomFieldsJson,
    String contractHistoryCustomFieldsJson
  ) {
    return saveEstimate(
      opportunityId,
      selectedType,
      contractServiceName,
      contractHistoryName,
      contractServiceId,
      previousHistoryId,
      contractStartDate,
      contractEndDate,
      effectiveDate,
      applicationDate,
      productsJson,
      estimateRemarkMasterId,
      remarksText,
      billingAccountId,
      copyFromHistoryId,
      editHistoryId,
      contractServiceCustomFieldsJson,
      contractHistoryCustomFieldsJson,
      resolveCurrentHistoryToken(editHistoryId)
    );
  }

  /** Apex テスト互換。税・見積日は未指定。 */
  public static EstimateSaveResult saveEstimate(
    Id opportunityId,
    String selectedType,
    String contractServiceName,
    String contractHistoryName,
    Id contractServiceId,
    Id previousHistoryId,
    String contractStartDate,
    String contractEndDate,
    String effectiveDate,
    String applicationDate,
    String productsJson,
    Id estimateRemarkMasterId,
    String remarksText,
    Id billingAccountId,
    Id copyFromHistoryId,
    Id editHistoryId,
    String contractServiceCustomFieldsJson,
    String contractHistoryCustomFieldsJson,
    String expectedLastModifiedToken
  ) {
    return saveEstimate(
      opportunityId,
      selectedType,
      contractServiceName,
      contractHistoryName,
      contractServiceId,
      previousHistoryId,
      contractStartDate,
      contractEndDate,
      effectiveDate,
      applicationDate,
      productsJson,
      estimateRemarkMasterId,
      remarksText,
      billingAccountId,
      copyFromHistoryId,
      editHistoryId,
      contractServiceCustomFieldsJson,
      contractHistoryCustomFieldsJson,
      expectedLastModifiedToken,
      null,
      null,
      null,
      null
    );
  }

  /** Apex テスト互換。操作キー未指定。 */
  public static EstimateSaveResult saveEstimate(
    Id opportunityId,
    String selectedType,
    String contractServiceName,
    String contractHistoryName,
    Id contractServiceId,
    Id previousHistoryId,
    String contractStartDate,
    String contractEndDate,
    String effectiveDate,
    String applicationDate,
    String productsJson,
    Id estimateRemarkMasterId,
    String remarksText,
    Id billingAccountId,
    Id copyFromHistoryId,
    Id editHistoryId,
    String contractServiceCustomFieldsJson,
    String contractHistoryCustomFieldsJson,
    String expectedLastModifiedToken,
    Decimal taxPercent,
    String estimateDate,
    String estimateValidDate,
    Id estimateSendContactId
  ) {
    return saveEstimate(
      opportunityId,
      selectedType,
      contractServiceName,
      contractHistoryName,
      contractServiceId,
      previousHistoryId,
      contractStartDate,
      contractEndDate,
      effectiveDate,
      applicationDate,
      productsJson,
      estimateRemarkMasterId,
      remarksText,
      billingAccountId,
      copyFromHistoryId,
      editHistoryId,
      contractServiceCustomFieldsJson,
      contractHistoryCustomFieldsJson,
      expectedLastModifiedToken,
      taxPercent,
      estimateDate,
      estimateValidDate,
      estimateSendContactId,
      null
    );
  }

  /** 仕様: Core 第4.3.12節、共通基盤 第10.4節。見積のキー発行は 03。 */
  @AuraEnabled
  public static String issueEstimateOperationKey() {
    ContractPermissionUtil.assertEstimateSave(null, null);
    return AccountingCauseLockService.issueOperationKey();
  }

  /** 仕様: Core 第4.3.12節 */
  @AuraEnabled
  public static EstimateSaveResult saveEstimate(
    Id opportunityId,
    String selectedType,
    String contractServiceName,
    String contractHistoryName,
    Id contractServiceId,
    Id previousHistoryId,
    String contractStartDate,
    String contractEndDate,
    String effectiveDate,
    String applicationDate,
    String productsJson,
    Id estimateRemarkMasterId,
    String remarksText,
    Id billingAccountId,
    Id copyFromHistoryId,
    Id editHistoryId,
    String contractServiceCustomFieldsJson,
    String contractHistoryCustomFieldsJson,
    String expectedLastModifiedToken,
    Decimal taxPercent,
    String estimateDate,
    String estimateValidDate,
    Id estimateSendContactId,
    String businessOperationKey
  ) {
    ContractPermissionUtil.assertEstimateSave(editHistoryId, copyFromHistoryId);
    return EstimateSaveService.saveEstimate(
      opportunityId,
      selectedType,
      contractServiceName,
      contractHistoryName,
      contractServiceId,
      previousHistoryId,
      contractStartDate,
      contractEndDate,
      effectiveDate,
      applicationDate,
      productsJson,
      estimateRemarkMasterId,
      remarksText,
      billingAccountId,
      copyFromHistoryId,
      editHistoryId,
      contractServiceCustomFieldsJson,
      contractHistoryCustomFieldsJson,
      expectedLastModifiedToken,
      taxPercent,
      estimateDate,
      estimateValidDate,
      estimateSendContactId,
      businessOperationKey
    );
  }

  /** Apex テスト互換 overload 用。外部公開の編集 API は token 必須。 */
  private static String resolveCurrentHistoryToken(Id contractHistoryId) {
    return ContractOptimisticLockUtil.toHistoryProductToken(contractHistoryId);
  }

  public class DocumentDefaultsDto {
    @AuraEnabled
    public Integer estimateValidMonths;

    @AuraEnabled
    public Integer defaultMonthlyCycles;

    @AuraEnabled
    public String estimateSendMode;

    @AuraEnabled
    public String today;

    /** 仕様: Core 第11.9節。DOWN / HALF_UP / UP。無い・空は既定へ落とさない。 */
    @AuraEnabled
    public String taxRoundingMode;

    /** 仕様: Core 第4.6節、第11.9節。Scale2HalfUp 等。無い・空は既定へ落とさない。 */
    @AuraEnabled
    public String quantityUnitPriceRoundingMode;

    /** 仕様: Core 第4.6節、第11.9節。Scale0HalfUp 等。無い・空は既定へ落とさない。 */
    @AuraEnabled
    public String amountRoundingMode;
  }

  /** 仕様: Core 第4.10節、第11.9節、第4.3.1節、日付仕様 第2.5節・第2.6節・第8章、共通基盤 第10.4節 */
  @AuraEnabled(cacheable=true)
  public static DocumentDefaultsDto getDocumentDefaults() {
    ContractPermissionUtil.assertEstimateDocumentDefaults();
    DocumentDefaultsDto dto = new DocumentDefaultsDto();
    dto.estimateValidMonths = ContractDocumentSettingService.requireEstimateValidMonths();
    dto.defaultMonthlyCycles = ContractDocumentSettingService.requireDefaultCycles();
    dto.estimateSendMode = ContractDocumentSettingService.requireSendMode('Estimate');
    dto.today = String.valueOf(
      InvoiceTransactionStatusService.organizationToday()
    );
    GlAccountingSetting__mdt amountSetting = AmountCalculationSettingService.requireOrgDefault();
    dto.taxRoundingMode = amountSetting.TaxRoundingMode__c;
    dto.quantityUnitPriceRoundingMode = amountSetting.QuantityUnitPriceRoundingMode__c;
    dto.amountRoundingMode = amountSetting.AmountRoundingMode__c;
    return dto;
  }

  /**
   * テスト互換用ファサード。実装は EstimateSaveService。
   */
  @TestVisible
  public static Decimal resolveEstimateHistoryVersion(
    Id contractServiceId,
    Id copyFromHistoryId
  ) {
    return EstimateSaveService.resolveEstimateHistoryVersion(
      contractServiceId,
      copyFromHistoryId
    );
  }
}
