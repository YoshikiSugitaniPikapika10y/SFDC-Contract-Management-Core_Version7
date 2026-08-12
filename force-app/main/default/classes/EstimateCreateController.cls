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

    /** InTerm / OutOfTerm / SPOT など */
    @AuraEnabled
    public String status;

    /** 表示用: 期間内 / 期間外 / 都度 */
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
    return EstimateQueryService.getRecurringContractProducts(contractHistoryId);
  }

  @AuraEnabled
  public static List<ContractProductLineDto> getRenewContractProducts(
    Id contractServiceId
  ) {
    return EstimateQueryService.getRenewContractProducts(contractServiceId);
  }

  @AuraEnabled
  public static ContractHistoryDto getLatestContractHistory(
    Id contractServiceId
  ) {
    return EstimateQueryService.getLatestContractHistory(contractServiceId);
  }

  @AuraEnabled
  public static ContractHistoryDto getContractHistoryInfo(
    Id contractHistoryId
  ) {
    return EstimateQueryService.getContractHistoryInfo(contractHistoryId);
  }

  @AuraEnabled
  public static Id getEstimateCopyLaunchInfo(Id contractHistoryId) {
    return EstimateQueryService.getEstimateCopyLaunchInfo(contractHistoryId);
  }

  @AuraEnabled
  public static EstimateCopyPresetDto getEstimateCopyPreset(
    Id contractHistoryId
  ) {
    ContractPermissionUtil.assertHas(
      ContractPermissionUtil.COPY_ESTIMATE,
      '見積コピーを実行する権限がありません。'
    );
    return EstimateQueryService.getEstimateCopyPreset(contractHistoryId);
  }

  @AuraEnabled
  public static EstimateCopyPresetDto getEstimateEditPreset(
    Id contractHistoryId
  ) {
    ContractPermissionUtil.assertHas(
      ContractPermissionUtil.EDIT_ESTIMATE,
      '見積編集を実行する権限がありません。'
    );
    return EstimateQueryService.getEstimateEditPreset(contractHistoryId);
  }

  @AuraEnabled
  public static ProductDefaultDto getProductDefaults(Id productId) {
    return EstimateQueryService.getProductDefaults(productId);
  }

  @AuraEnabled(cacheable=true)
  public static List<ContractMetadataService.InvoiceSettingOption> getInvoiceSettingOptions() {
    return EstimateQueryService.getInvoiceSettingOptions();
  }

  @AuraEnabled(cacheable=true)
  public static String getDefaultInvoiceSettingLabel() {
    return EstimateQueryService.getDefaultInvoiceSettingLabel();
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
      null
    );
  }

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
    String expectedLastModifiedToken
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
      expectedLastModifiedToken
    );
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
