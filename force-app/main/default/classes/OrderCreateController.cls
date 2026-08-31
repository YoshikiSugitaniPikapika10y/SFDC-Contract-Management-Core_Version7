/**
 * 受注ウィザード（orderCreate*）向け Apex コントローラ。
 * 見積→受注、取消、請求ロック確認などのサーバ処理を提供する。
 */
public without sharing class OrderCreateController {
  private static final String HISTORY_STATUS_ESTIMATE = ContractDomainConstants.HISTORY_STATUS_ESTIMATE;
  private static final String HISTORY_STATUS_ORDERED = ContractDomainConstants.HISTORY_STATUS_ORDERED;
  private static final String HISTORY_TYPE_CANCEL = ContractDomainConstants.HISTORY_TYPE_CANCEL;
  @TestVisible
  private static final String ORDER_TOKEN_REQUIRED_MESSAGE = '受注対象が更新された可能性があります。画面を開き直してから再度操作してください。';
  @TestVisible
  private static Boolean testHasOrderPermission = true;
  @TestVisible
  private static Boolean testHasRevertPermission = true;

  public class OrderContextDto {
    @AuraEnabled
    public Id contractHistoryId;

    @AuraEnabled
    public Id contractServiceId;

    @AuraEnabled
    public String historyName;

    @AuraEnabled
    public String historyType;

    @AuraEnabled
    public String historyStatus;

    @AuraEnabled
    public Decimal version;

    @AuraEnabled
    public String termStartDate;

    @AuraEnabled
    public String termEndDate;

    @AuraEnabled
    public String effectiveDate;

    @AuraEnabled
    public String contractServiceName;

    @AuraEnabled
    public String accountName;

    @AuraEnabled
    public Id billingAccountId;

    @AuraEnabled
    public String billingAccountName;

    @AuraEnabled
    public String billingCustomerAccountName;

    @AuraEnabled
    public String billingAddressee;

    @AuraEnabled
    public String billingEmailTo;

    @AuraEnabled
    public String billingEmailCc;

    @AuraEnabled
    public String billingEmailBcc;

    @AuraEnabled
    public EstimateCreateController.BillingAccountInvoiceSettingsDto billingSettings;

    @AuraEnabled
    public Map<String, Object> historyCustomFields;

    @AuraEnabled
    public List<ContractWizardFieldService.WizardFieldDefinition> historyFieldDefinitions;

    @AuraEnabled
    public Map<String, Object> historySavedFields;

    @AuraEnabled
    public Map<String, Object> billingCustomFields;

    @AuraEnabled
    public List<ProductLineDto> products;

    @AuraEnabled
    public Boolean isOrdered;

    @AuraEnabled
    public Boolean canOrder;

    @AuraEnabled
    public Boolean canRevert;

    @AuraEnabled
    public String revertBlockedReason;

    /** 受注画面で「更新商談を作成」を出すか（Cancel / Spot 以外の Estimate） */
    @AuraEnabled
    public Boolean showCreateRenewOpportunity;

    /** 見積で保存された更新商談作成要求 */
    @AuraEnabled
    public Boolean createRenewOpportunity;

    /** 差し戻し画面で「更新商談を削除」を出すか（スイッチONかつ作成済みがある） */
    @AuraEnabled
    public Boolean hasRenewOpportunity;

    @AuraEnabled
    public Id renewOpportunityId;

    /** 同時編集ガード用。契約履歴と配下見積商品の最大更新時刻 */
    @AuraEnabled
    public String lastModifiedToken;
  }

  public class ProductLineDto {
    @AuraEnabled
    public String productName;

    @AuraEnabled
    public Decimal quantity;

    @AuraEnabled
    public Decimal unitPrice;

    @AuraEnabled
    public String unit;

    @AuraEnabled
    public String billingType;

    @AuraEnabled
    public String invoiceSetting;

    @AuraEnabled
    public String startDate;

    @AuraEnabled
    public String endDate;

    @AuraEnabled
    public Decimal lineAmount;
  }

  public class OrderSaveResult {
    @AuraEnabled
    public Id contractHistoryId;

    @AuraEnabled
    public String historyStatus;

    @AuraEnabled
    public Id renewOpportunityId;

    @AuraEnabled
    public String businessOperationKey;
  }

  public class InvoicePreviewDto {
    @AuraEnabled
    public Decimal totalAmount;

    @AuraEnabled
    public Decimal totalTaxAmount;

    @AuraEnabled
    public Decimal integratedAmount;

    @AuraEnabled
    public Decimal clearedAmount;

    @AuraEnabled
    public Decimal openAmount;

    @AuraEnabled
    public Integer invoiceCount;

    @AuraEnabled
    public Integer lineCount;

    @AuraEnabled
    public List<InvoiceGroupDto> invoices;

    @AuraEnabled
    public List<VersionOptionDto> versionOptions;

    /**
     * プレビューを開いた契約履歴の Version（フィルタ value と同形式の数字文字列）。
     * LWC の Version フィルタ初期値に使う。全バージョン表示へは手動切替可。
     */
    @AuraEnabled
    public String sourceHistoryVersion;

    @AuraEnabled
    public Boolean canView;

    @AuraEnabled
    public Boolean canEdit;

    @AuraEnabled
    public Boolean versionEditBlocked;

    /**
     * 見積額（比較用）。Ordered 契約商品 Amount を、請求に載った月数で按分した合計。
     * 継続: Amount × (InvoiceProduct件数 / CP月数)。一回: 請求明細があれば Amount 全額。
     */
    @AuraEnabled
    public Decimal periodLineAmountTotal;

    @AuraEnabled
    public Decimal periodLineTaxInclusiveTotal;

    @AuraEnabled
    public Decimal invoiceAmountTotal;

    @AuraEnabled
    public Decimal invoiceTaxInclusiveTotal;

    @AuraEnabled
    public Decimal amountDifference;

    /**
     * 端数調整の実績。由来付き明細金額合計 − 由来 InvoiceProduct 金額合計
     *（期間 ID は重複排除。請求日／BA 分割後の偽マイナスを防ぐ）。
     * 見積と請求が一致していても、手動調整していれば非ゼロになり得る。
     */
    @AuraEnabled
    public Decimal manualAdjustmentAmount;

    @AuraEnabled
    public Boolean hasManualAdjustment;

    /**
     * 同時編集ガード用。当該契約サービスの請求 Invoice の
     * MAX(LastModifiedDate) を epoch ms 文字列にしたもの。
     */
    @AuraEnabled
    public String contentVersion;

    @AuraEnabled
    public String invoiceSendMode;

    /** 仕様: 日付仕様 第8章。組織タイムゾーンの操作日（YYYY-MM-DD）。 */
    @AuraEnabled
    public Date operationDay;

    /** 仕様: Core 第11.9節。DOWN / HALF_UP / UP。無い・空は既定へ落とさない。 */
    @AuraEnabled
    public String taxRoundingMode;

    /** 仕様: Core 第11.9節。Scale2HalfUp 等。無い・空は既定へ落とさない。 */
    @AuraEnabled
    public String quantityUnitPriceRoundingMode;

    /** 仕様: Core 第11.9節。Scale0HalfUp 等。無い・空は既定へ落とさない。 */
    @AuraEnabled
    public String amountRoundingMode;

    /** 仕様: Core 第11.6節、第11.4.4節。確定後／登録後／Lock後の編集可否。 */
    @AuraEnabled
    public List<String> invoiceLockExemptFieldApiNames;
    @AuraEnabled
    public List<String> paymentLockExemptFieldApiNames;
    @AuraEnabled
    public List<String> journalLockExemptFieldApiNames;
  }

  public class PreviewScopeDto {
    @AuraEnabled
    public Id recordId;

    @AuraEnabled
    public String objectApiName;

    @AuraEnabled
    public Id contractHistoryId;

    @AuraEnabled
    public Id contractServiceId;

    @AuraEnabled
    public Id invoiceId;

    @AuraEnabled
    public String initialVersion;

    @AuraEnabled
    public Id initialInvoiceId;

    @AuraEnabled
    public Boolean canOpen;

    @AuraEnabled
    public String blockReason;
  }

  public class VersionOptionDto {
    @AuraEnabled
    public String value;

    @AuraEnabled
    public String label;

    @AuraEnabled
    public Decimal version;

    @AuraEnabled
    public Decimal periodLineAmountTotal;

    @AuraEnabled
    public Decimal periodLineTaxInclusiveTotal;

    @AuraEnabled
    public Decimal invoiceAmountTotal;

    @AuraEnabled
    public Decimal invoiceTaxInclusiveTotal;

    @AuraEnabled
    public Decimal amountDifference;

    @AuraEnabled
    public Decimal manualAdjustmentAmount;
  }

  public class InvoiceGroupDto {
    @AuraEnabled
    public Id invoiceId;

    @AuraEnabled
    public String invoiceName;

    @AuraEnabled
    public String mergeKey;

    @AuraEnabled
    public String contractServiceName;

    @AuraEnabled
    public Id billingAccountId;

    @AuraEnabled
    public String billingAccountName;

    @AuraEnabled
    public String billingAddressee;

    @AuraEnabled
    public String billingEmailTo;

    @AuraEnabled
    public String billingEmailCc;

    @AuraEnabled
    public String billingEmailBcc;

    @AuraEnabled
    public String invoiceDeliveryMethod;

    @AuraEnabled
    public String paymentTerm;

    @AuraEnabled
    public String invoiceDate;

    @AuraEnabled
    public String paymentScheduledDate;

    @AuraEnabled
    public Decimal amountTotal;

    @AuraEnabled
    public Decimal taxTotal;

    @AuraEnabled
    public Decimal taxPercent;

    @AuraEnabled
    public Decimal integratedAmount;

    @AuraEnabled
    public Decimal clearedAmount;

    @AuraEnabled
    public Decimal openAmount;

    @AuraEnabled
    public Boolean isManuallyAdjusted;

    /** 端数調整（±円）あり */
    @AuraEnabled
    public Boolean isAmountAdjusted;

    /** 分割・移動（請求を分ける／明細を移す／行分割）あり */
    @AuraEnabled
    public Boolean isSplitMoved;

    @AuraEnabled
    public Decimal historyVersion;

    /** 連携済または消込済（請求書単位ロック）。プレビュー編集の可否に使う。 */
    @AuraEnabled
    public Boolean locked;

    @AuraEnabled
    public String invoiceTransactionStatus;

    /** 仕様: Core 第7.10節、第7.11節 */
    @AuraEnabled
    public String deliveryStatus;

    /** 仕様: Core 第7.11節 */
    @AuraEnabled
    public String dueStatus;

    @AuraEnabled
    public Decimal overdueDays;

    @AuraEnabled
    public String accountingStatus;

    @AuraEnabled
    public String accountingIssueName;

    @AuraEnabled
    public Date sentDate;

    /** 仕様: Core 第7.7.3節、第7.10節。印付きのうち最新の発行PDF。 */
    @AuraEnabled
    public Id latestIssuedContentDocumentId;

    @AuraEnabled
    public Decimal paymentNetTotal;

    @AuraEnabled
    public Boolean canConfirm;

    @AuraEnabled
    public Boolean canUnconfirm;

    @AuraEnabled
    public String confirmationReason;

    @AuraEnabled
    public String lastModifiedToken;

    @AuraEnabled
    public String memo;

    @AuraEnabled
    public Boolean isCancelled;

    /** 仕様: Core 第11.4.4節。請求操作追加項目の現在値。 */
    @AuraEnabled
    public Map<String, Object> extraFieldValues;

    @AuraEnabled
    public Decimal invoicePaymentNet;

    @AuraEnabled
    public Decimal taxInclusiveAmount;

    @AuraEnabled
    public List<InvoiceMergedLineDto> lines;
  }

  public class InvoiceMergedLineDto {
    @AuraEnabled
    public Id lineId;

    @AuraEnabled
    public String lineMergeKey;

    @AuraEnabled
    public String productName;

    @AuraEnabled
    public String historyVersionLabel;

    @AuraEnabled
    public List<Decimal> historyVersions;

    @AuraEnabled
    public Decimal unitPrice;

    @AuraEnabled
    public String unit;

    @AuraEnabled
    public Decimal quantity;

    @AuraEnabled
    public String periodLabel;

    /** ウィザード同様。継続課金は "N month"、それ以外は "-" */
    @AuraEnabled
    public String cycleCountLabel;

    @AuraEnabled
    public Decimal amount;

    @AuraEnabled
    public Decimal taxAmount;

    @AuraEnabled
    public Decimal integratedAmount;

    @AuraEnabled
    public Decimal clearedAmount;

    @AuraEnabled
    public Decimal openAmount;

    @AuraEnabled
    public Boolean isManuallyAdjusted;

    @AuraEnabled
    public Boolean isAmountAdjusted;

    @AuraEnabled
    public Boolean isSplitMoved;

    @AuraEnabled
    public List<Id> sourceInvoiceProductIds;

    /**
     * 見積側の比較基準額。
     * 契約商品 Amount を CP 月数で割り、この明細に載った月数分へ按分した値。
     * 上部バーの「見積額」と同じ定義（InvoiceProduct 金額の合算ではない）。
     */
    @AuraEnabled
    public Decimal sourceAmountTotal;

    /** 請求明細金額 − 見積按分額。0 なら端数なし */
    @AuraEnabled
    public Decimal amountDeltaFromSource;

    @AuraEnabled
    public Boolean hasAmountDrift;

    @AuraEnabled
    public Id contractProductId;

    /** 継続課金なら true（請求プレビューの月分割候補表示用） */
    @AuraEnabled
    public Boolean isRecurring;

    /** 検収終了日。確定済み請求でも編集できる（仕訳計上日の候補） */
    @AuraEnabled
    public Date acceptanceEndDate;

    /** 仕様: Core 第7.6節 */
    @AuraEnabled
    public String revenueRecognitionBasis;
  }

  /** 仕様: Core 第11.4.3節、第5.2節、第11.5節、共通基盤 第10.4節。受注ウィザードは 06、差し戻しは 07。 */
  @AuraEnabled
  public static OrderContextDto getOrderContext(Id contractHistoryId) {
    if (contractHistoryId == null) {
      throw toAuraHandled('契約履歴IDが指定されていません。');
    }
    if (!hasOrderPermission() && !hasRevertPermission()) {
      throw toAuraHandled('この操作を実行する権限がありません。');
    }

    List<ContractHistory__c> histories;
    try {
      histories = queryContractHistoryForOrderContext(contractHistoryId);
    } catch (OrderWizardFieldService.WizardFieldConfigException ex) {
      throw toAuraHandled(ex.getMessage());
    }
    if (histories.isEmpty()) {
      throw toAuraHandled('契約履歴が見つかりません。');
    }

    ContractHistory__c history = histories[0];
    OrderContextDto dto = new OrderContextDto();
    dto.contractHistoryId = history.Id;
    dto.contractServiceId = history.ContractService__c;
    dto.historyName = history.Name;
    dto.historyType = history.Type__c;
    dto.historyStatus = history.historystatus__c;
    dto.version = history.Version__c;
    dto.termStartDate = formatDate(history.CurrentTermStartDate__c);
    dto.termEndDate = formatDate(history.CurrentTermEndDate__c);
    dto.effectiveDate = formatDate(history.EffectiveDate__c);
    dto.contractServiceName = history.ContractService__r.Name;
    dto.accountName = history.ContractService__r.Account__r == null
      ? null
      : history.ContractService__r.Account__r.Name;
    dto.billingAccountId = history.ContractService__r.BiilingAcccount__c;
    dto.billingAccountName = history.ContractService__r.BiilingAcccount__r ==
      null
      ? null
      : history.ContractService__r.BiilingAcccount__r.Name;
    dto.billingCustomerAccountName = history.ContractService__r.BiilingAcccount__r ==
      null ||
      history.ContractService__r.BiilingAcccount__r.Account__r == null
      ? null
      : history.ContractService__r.BiilingAcccount__r.Account__r.Name;
    if (history.ContractService__r.BiilingAcccount__r != null) {
      BillingAccount__c billingAccount = history.ContractService__r.BiilingAcccount__r;
      dto.billingEmailTo = billingAccount.BillingEmailTo__c;
      dto.billingEmailCc = billingAccount.BillingEmailCc__c;
      dto.billingEmailBcc = billingAccount.BillingEmailBcc__c;
      dto.billingAddressee = billingAccount.BillingAddressee__c;
    }
    dto.isOrdered = history.historystatus__c == HISTORY_STATUS_ORDERED;
    dto.canOrder =
      hasOrderPermission() &&
      history.historystatus__c == HISTORY_STATUS_ESTIMATE;
    dto.revertBlockedReason = buildRevertBlockedReason(
      history.Id,
      history.historystatus__c
    );
    dto.canRevert =
      hasRevertPermission() &&
      history.historystatus__c == HISTORY_STATUS_ORDERED &&
      String.isBlank(dto.revertBlockedReason);
    dto.showCreateRenewOpportunity =
      history.historystatus__c == HISTORY_STATUS_ESTIMATE &&
      ContractDocumentSettingService.requireRenewOpportunitySwitch() &&
      !shouldSkipRenewOpportunity(history);
    // 仕様: Core 第5.2節、第11.5節。保存値ではなく画面初期状態をONにする。
    dto.createRenewOpportunity = dto.showCreateRenewOpportunity;
    dto.renewOpportunityId = RenewOpportunityCreateService.findBySourceHistory(
      history.Id
    );
    // 仕様: Core 第5.6節、第11.5節。OFFなら削除選択もカウントも動かない。
    dto.hasRenewOpportunity =
      dto.renewOpportunityId != null &&
      ContractDocumentSettingService.requireRenewOpportunitySwitch();
    dto.lastModifiedToken = ContractOptimisticLockUtil.toHistoryProductToken(
      history.Id
    );
    dto.products = loadProductLines(history.Id);
    dto.billingSettings = buildBillingSettings(
      history.ContractService__r.BiilingAcccount__r
    );
    try {
      dto.historyFieldDefinitions = OrderWizardFieldService.getDefinitions(
        history.Type__c
      );
      dto.historyCustomFields = OrderWizardFieldService.buildHistoryFieldValuesForWizard(
        history
      );
      dto.historySavedFields = OrderWizardFieldService.buildHistoryCustomFieldValues(
        history
      );
    } catch (OrderWizardFieldService.WizardFieldConfigException ex) {
      throw toAuraHandled(ex.getMessage());
    }
    dto.billingCustomFields = buildBillingCustomFields(
      history.ContractService__r.BiilingAcccount__r
    );
    return dto;
  }

  /** Apex テスト互換。Aura 公開入口は LastModified トークン必須。 */
  @TestVisible
  private static OrderSaveResult revertOrder(
    Id contractHistoryId,
    Boolean deleteRenewOpportunity
  ) {
    ContractHistory__c history = loadOrderedHistory(contractHistoryId);
    return revertOrder(
      contractHistoryId,
      deleteRenewOpportunity,
      ContractOptimisticLockUtil.toHistoryProductToken(history.Id),
      null
    );
  }

  @TestVisible
  private static OrderSaveResult revertOrder(
    Id contractHistoryId,
    Boolean deleteRenewOpportunity,
    String expectedLastModifiedToken
  ) {
    return revertOrder(
      contractHistoryId,
      deleteRenewOpportunity,
      expectedLastModifiedToken,
      null,
      null
    );
  }

  public static OrderSaveResult revertOrder(
    Id contractHistoryId,
    Boolean deleteRenewOpportunity,
    String expectedLastModifiedToken,
    String historyCustomFieldsJson
  ) {
    return revertOrder(
      contractHistoryId,
      deleteRenewOpportunity,
      expectedLastModifiedToken,
      historyCustomFieldsJson,
      null
    );
  }

  /** 仕様: Core 第5.3節、第4.3.12節、第11.4.3節、第11.5節 */
  @AuraEnabled
  public static OrderSaveResult revertOrder(
    Id contractHistoryId,
    Boolean deleteRenewOpportunity,
    String expectedLastModifiedToken,
    String historyCustomFieldsJson,
    String businessOperationKey
  ) {
    assertRevertPermission();
    String operationKey = AccountingCauseLockService.resolveOrIssueOperationKey(
      businessOperationKey
    );
    List<ContractHistory__c> histories;
    try {
      histories = queryContractHistoryForOrderContext(contractHistoryId, true);
    } catch (OrderWizardFieldService.WizardFieldConfigException ex) {
      throw toAuraHandled(ex.getMessage());
    }
    if (histories.isEmpty()) {
      throw toAuraHandled('契約履歴が見つかりません。');
    }
    ContractHistory__c history = histories[0];
    if (
      history.historystatus__c == HISTORY_STATUS_ESTIMATE &&
      history.BusinessOperationKey__c == operationKey
    ) {
      OrderSaveResult existing = new OrderSaveResult();
      existing.contractHistoryId = history.Id;
      existing.historyStatus = HISTORY_STATUS_ESTIMATE;
      existing.businessOperationKey = operationKey;
      ContractOperationLogService.write(
        'RevertOrder',
        operationKey,
        'ContractHistory__c',
        String.valueOf(history.Id)
      );
      return existing;
    }
    if (history.historystatus__c != HISTORY_STATUS_ORDERED) {
      throw toAuraHandled('受注済み状態の契約履歴のみ差し戻しできます。');
    }
    ContractOptimisticLockUtil.assertRequiredHistoryProductsUnchanged(
      history.Id,
      expectedLastModifiedToken
    );
    String blockedReason = buildRevertBlockedReason(
      history.Id,
      history.historystatus__c
    );
    if (String.isNotBlank(blockedReason)) {
      throw toAuraHandled(blockedReason);
    }

    if (historyCustomFieldsJson != null) {
      Map<String, Object> historyFields = parseCustomFields(
        historyCustomFieldsJson
      );
      try {
        OrderWizardFieldService.applyHistoryFields(history, historyFields);
      } catch (OrderWizardFieldService.WizardFieldConfigException ex) {
        throw toAuraHandled(ex.getMessage());
      }
    }
    history.OrderDate__c = null;
    history.historystatus__c = HISTORY_STATUS_ESTIMATE;
    history.BusinessOperationKey__c = operationKey;
    // 仕様: Core 第5.3節・第5.6節。画面外は受注日以外を触らない。
    if (historyCustomFieldsJson != null) {
      history.CreateRenewOpportunity__c = false;
    }
    Savepoint revertSavepoint = Database.setSavepoint();
    try {
      SystemContextAccess.updateRecords(
        new List<ContractHistory__c>{ history }
      );
      if (
        historyCustomFieldsJson != null &&
        deleteRenewOpportunity == true &&
        ContractDocumentSettingService.requireRenewOpportunitySwitch()
      ) {
        RenewOpportunityCreateService.deleteBySourceHistory(history.Id);
      }
    } catch (RenewOpportunityCreateService.RenewOpportunityException ex) {
      Database.rollback(revertSavepoint);
      throw toAuraHandled(ex.getMessage());
    } catch (DmlException ex) {
      Database.rollback(revertSavepoint);
      throw toAuraHandled(extractDmlMessage(ex));
    } catch (Exception ex) {
      Database.rollback(revertSavepoint);
      throw toAuraHandled(
        String.isNotBlank(ex.getMessage())
          ? ex.getMessage()
          : '差し戻し処理中にエラーが発生しました。'
      );
    }

    OrderSaveResult result = new OrderSaveResult();
    result.contractHistoryId = history.Id;
    result.historyStatus = HISTORY_STATUS_ESTIMATE;
    result.businessOperationKey = operationKey;
    ContractOperationLogService.write(
      'RevertOrder',
      operationKey,
      'ContractHistory__c',
      String.valueOf(history.Id)
    );
    return result;
  }

  /** Apex テスト専用の互換入口。本番の Aura 入口は更新トークン必須。 */
  @TestVisible
  private static OrderSaveResult confirmOrder(
    Id contractHistoryId,
    String billingCustomFieldsJson,
    Boolean createRenewOpportunity
  ) {
    return confirmOrderInternal(
      contractHistoryId,
      billingCustomFieldsJson,
      createRenewOpportunity,
      null,
      false,
      null,
      null
    );
  }

  /** 仕様: Core 第5.2節、第11.5節 */
  public static OrderSaveResult confirmOrder(
    Id contractHistoryId,
    String billingCustomFieldsJson,
    Boolean createRenewOpportunity,
    String expectedLastModifiedToken
  ) {
    return confirmOrderInternal(
      contractHistoryId,
      billingCustomFieldsJson,
      createRenewOpportunity,
      expectedLastModifiedToken,
      true,
      null,
      null
    );
  }

  /** 仕様: Core 第5.2節、第11.5節 */
  public static OrderSaveResult confirmOrder(
    Id contractHistoryId,
    String billingCustomFieldsJson,
    Boolean createRenewOpportunity,
    String expectedLastModifiedToken,
    String historyCustomFieldsJson
  ) {
    return confirmOrderInternal(
      contractHistoryId,
      billingCustomFieldsJson,
      createRenewOpportunity,
      expectedLastModifiedToken,
      true,
      historyCustomFieldsJson,
      null
    );
  }

  /** 仕様: Core 第5.2節、第4.3.12節、第11.5節 */
  @AuraEnabled
  public static OrderSaveResult confirmOrder(
    Id contractHistoryId,
    String billingCustomFieldsJson,
    Boolean createRenewOpportunity,
    String expectedLastModifiedToken,
    String historyCustomFieldsJson,
    String businessOperationKey
  ) {
    return confirmOrderInternal(
      contractHistoryId,
      billingCustomFieldsJson,
      createRenewOpportunity,
      expectedLastModifiedToken,
      true,
      historyCustomFieldsJson,
      businessOperationKey
    );
  }

  /** 仕様: Core 第4.3.12節、共通基盤 第10.4節。受注のキー発行は 06。 */
  @AuraEnabled
  public static String issueOrderOperationKey() {
    assertOrderPermission();
    return AccountingCauseLockService.issueOperationKey();
  }

  /** 仕様: Core 第5.2節、第4.3.12節、第11.5節 */
  private static OrderSaveResult confirmOrderInternal(
    Id contractHistoryId,
    String billingCustomFieldsJson,
    Boolean createRenewOpportunity,
    String expectedLastModifiedToken,
    Boolean requireToken,
    String historyCustomFieldsJson,
    String businessOperationKey
  ) {
    assertOrderPermission();
    FieldCopyDefinitionService.validateAllDefinitions();
    if (requireToken && String.isBlank(expectedLastModifiedToken)) {
      throw toAuraHandled(ORDER_TOKEN_REQUIRED_MESSAGE);
    }
    String operationKey = AccountingCauseLockService.resolveOrIssueOperationKey(
      businessOperationKey
    );
    ContractHistory__c history;
    try {
      List<ContractHistory__c> locked = queryEstimateHistoryForEdit(
        contractHistoryId,
        true
      );
      if (locked.isEmpty()) {
        throw toAuraHandled('契約履歴が見つかりません。');
      }
      history = locked[0];
    } catch (OrderWizardFieldService.WizardFieldConfigException ex) {
      throw toAuraHandled(ex.getMessage());
    }
    if (
      history.historystatus__c == HISTORY_STATUS_ORDERED &&
      history.BusinessOperationKey__c == operationKey
    ) {
      OrderSaveResult existing = new OrderSaveResult();
      existing.contractHistoryId = history.Id;
      existing.historyStatus = HISTORY_STATUS_ORDERED;
      existing.businessOperationKey = operationKey;
      existing.renewOpportunityId = history.RenewalOpportunity__c;
      ContractOperationLogService.write(
        'Order',
        operationKey,
        'ContractHistory__c',
        String.valueOf(history.Id)
      );
      return existing;
    }
    if (history.historystatus__c != HISTORY_STATUS_ESTIMATE) {
      if (requireToken) {
        throw ContractOptimisticLockUtil.conflict('契約履歴');
      }
      throw toAuraHandled('見積状態の契約履歴のみ編集できます。');
    }
    if (requireToken) {
      ContractOptimisticLockUtil.assertRequiredHistoryProductsUnchanged(
        history.Id,
        expectedLastModifiedToken
      );
    } else {
      ContractOptimisticLockUtil.assertUnchanged(
        ContractOptimisticLockUtil.resolveHistoryProductDatetime(history.Id),
        expectedLastModifiedToken,
        '契約履歴'
      );
    }
    validateReadyForOrder(history);
    if (historyCustomFieldsJson != null) {
      Map<String, Object> historyFields = parseCustomFields(
        historyCustomFieldsJson
      );
      try {
        String requiredError = OrderWizardFieldService.validateRequiredHistoryFields(
          historyFields,
          history.Type__c
        );
        if (String.isNotBlank(requiredError)) {
          throw toAuraHandled(requiredError);
        }
        OrderWizardFieldService.applyHistoryFields(history, historyFields);
      } catch (OrderWizardFieldService.WizardFieldConfigException ex) {
        throw toAuraHandled(ex.getMessage());
      }
    }

    Boolean renewSwitchOn = ContractDocumentSettingService.requireRenewOpportunitySwitch();
    if (createRenewOpportunity == true) {
      if (
        !renewSwitchOn ||
        shouldSkipRenewOpportunity(history)
      ) {
        throw toAuraHandled(
          ContractHistoryTriggerHandler.RENEW_REQUEST_NOT_ALLOWED_MESSAGE
        );
      }
    }
    Boolean requestRenew = createRenewOpportunity == true;
    history.historystatus__c = HISTORY_STATUS_ORDERED;
    history.BusinessOperationKey__c = operationKey;
    history.CreateRenewOpportunity__c = requestRenew;
    Id renewOpportunityId = null;
    Savepoint orderSavepoint = Database.setSavepoint();
    try {
      if (requestRenew) {
        Decimal currentCount = history.RenewOpportunityRequestCount__c;
        history.RenewOpportunityRequestCount__c = (currentCount == null
            ? 0
            : currentCount) + 1;
        /** 仕様: Core 第5.6節、第11.5節 */
        history.RenewalOpportunity__c = null;
      }
      SystemContextAccess.updateRecords(
        new List<ContractHistory__c>{ history }
      );
      if (requestRenew) {
        ContractHistory__c reloaded = [
          SELECT
            Id,
            ContractService__c,
            RenewalOpportunity__c,
            ContractService__r.Account__c
          FROM ContractHistory__c
          WHERE Id = :history.Id
          WITH SYSTEM_MODE
          LIMIT 1
        ];
        renewOpportunityId = reloaded.RenewalOpportunity__c;
        RenewOpportunityCreateService.assertCreatedForHistory(
          reloaded,
          renewOpportunityId
        );
      }
    } catch (RenewOpportunityCreateService.RenewOpportunityException ex) {
      Database.rollback(orderSavepoint);
      throw toAuraHandled(ex.getMessage());
    } catch (DmlException ex) {
      Database.rollback(orderSavepoint);
      throw toAuraHandled(extractConfirmOrderDmlMessage(ex));
    } catch (InvoiceLockUtil.InvoiceLockException ex) {
      Database.rollback(orderSavepoint);
      throw toAuraHandled(ex.getMessage());
    } catch (InvoiceProductFieldCopyService.FieldCopyException ex) {
      Database.rollback(orderSavepoint);
      throw toAuraHandled(ex.getMessage());
    } catch (FieldCopyDefinitionService.FieldCopyException ex) {
      Database.rollback(orderSavepoint);
      throw toAuraHandled(ex.getMessage());
    } catch (Exception ex) {
      Database.rollback(orderSavepoint);
      throw toAuraHandled(
        String.isNotBlank(ex.getMessage())
          ? ex.getMessage()
          : '受注処理中にエラーが発生しました。'
      );
    }

    OrderSaveResult result = new OrderSaveResult();
    result.contractHistoryId = history.Id;
    result.historyStatus = HISTORY_STATUS_ORDERED;
    result.renewOpportunityId = renewOpportunityId;
    result.businessOperationKey = operationKey;
    ContractOperationLogService.write(
      'Order',
      operationKey,
      'ContractHistory__c',
      String.valueOf(history.Id)
    );
    return result;
  }

  private static String extractConfirmOrderDmlMessage(DmlException ex) {
    if (ex == null) {
      return '受注処理中にエラーが発生しました。';
    }
    if (ex.getNumDml() > 0) {
      return ex.getDmlMessage(0);
    }
    return String.isNotBlank(ex.getMessage())
      ? ex.getMessage()
      : '受注処理中にエラーが発生しました。';
  }

  private static AuraHandledException toAuraHandled(String message) {
    String resolved = String.isNotBlank(message)
      ? message
      : '処理中にエラーが発生しました。';
    AuraHandledException ex = new AuraHandledException(resolved);
    ex.setMessage(resolved);
    return ex;
  }

  /** 仕様: Core 第7.7.0節 */
  @AuraEnabled
  public static PreviewScopeDto resolvePreviewScope(Id recordId) {
    ContractPermissionUtil.assertViewInvoicePreview();
    PreviewScopeDto scope = new PreviewScopeDto();
    scope.recordId = recordId;
    scope.canOpen = false;
    if (recordId == null) {
      scope.blockReason = '対象レコードが指定されていません。';
      return scope;
    }
    scope.objectApiName = recordId.getSObjectType().getDescribe().getName();
    if (scope.objectApiName == 'ContractHistory__c') {
      return fillScopeFromHistory(scope, recordId, null);
    }
    if (scope.objectApiName == 'ContractService__c') {
      return fillScopeFromService(scope, recordId);
    }
    if (scope.objectApiName == 'Invoice__c') {
      return fillScopeFromInvoice(scope, recordId);
    }
    scope.blockReason = '請求ボードは契約履歴・契約サービス・請求書から開きます。';
    return scope;
  }

  /** 仕様: Core 第7.7.0節、第7.6節、第11.3節、第1.1.10節 */
  @AuraEnabled
  public static InvoicePreviewDto getInvoicePreview(Id contractHistoryId) {
    ContractPermissionUtil.assertViewInvoicePreview();
    if (contractHistoryId == null) {
      return emptyPreview();
    }

    ContractHistory__c sourceHistory = resolveHistoryForPreview(
      contractHistoryId
    );
    if (sourceHistory == null || sourceHistory.ContractService__c == null) {
      return emptyPreview();
    }
    Id contractServiceId = sourceHistory.ContractService__c;

    // 請求正本の作成は受注時のみ。プレビュー open では作らない（欠けていれば空表示）。
    InvoicePreviewDto preview = buildInvoicePreviewFromCanonical(
      contractServiceId
    );
    try {
      InvoicePreviewIntegrityService.assertSameHistory(
        null,
        previewInvoicesForIntegrity(preview)
      );
    } catch (InvoicePreviewIntegrityService.IntegrityException ex) {
      throw toAuraHandled(ex.getMessage());
    }
    preview.versionOptions = loadOrderedVersionOptions(contractServiceId);
    enrichVersionAmountSummaries(preview, contractServiceId);
    applyManualAdjustmentAmounts(preview);
    applyEstimateDriftToLines(preview);
    preview.sourceHistoryVersion = sourceHistory.Version__c == null
      ? null
      : String.valueOf(sourceHistory.Version__c.intValue());
    preview.canView = true;
    preview.canEdit = InvoiceCanonicalService.canEditInvoicePreview();
    // プレビュー編集は請求書単位ロック（invoice.locked）。Version 一括ブロックは使わない。
    preview.versionEditBlocked = false;
    preview.contentVersion = resolvePreviewContentToken(contractServiceId);
    try {
      preview.invoiceSendMode = ContractDocumentSettingService.requireSendMode(
        'Invoice'
      );
    } catch (ContractDocumentSettingService.SettingException ex) {
      throw toAuraHandled(ex.getMessage());
    }
    return preview;
  }

  /** 仕様: Core 第7.9.7節、第4.3.12節。比較値未指定は拒否する。現在版で埋めない。 */
  public static InvoicePreviewDto updateInvoiceLineAmount(
    Id contractHistoryId,
    Id lineId,
    Decimal amount,
    String expectedContentVersion
  ) {
    InvoiceCanonicalService.LineAmountEdit edit = new InvoiceCanonicalService.LineAmountEdit();
    edit.lineId = lineId;
    edit.amount = amount;
    return updateInvoiceLineAmounts(
      contractHistoryId,
      new List<InvoiceCanonicalService.LineAmountEdit>{ edit },
      expectedContentVersion,
      null
    );
  }

  /** 仕様: Core 第7.9.7節、第4.3.12節。比較値未指定は拒否する。現在版で埋めない。 */
  public static InvoicePreviewDto updateInvoiceLineAmounts(
    Id contractHistoryId,
    List<InvoiceCanonicalService.LineAmountEdit> edits,
    String expectedContentVersion
  ) {
    return updateInvoiceLineAmounts(
      contractHistoryId,
      edits,
      expectedContentVersion,
      null
    );
  }

  /** 仕様: Core 第7.9.7節、第7.8節。端数調整は操作キーと行ロックと版を共有する。 */
  public static InvoicePreviewDto updateInvoiceLineAmounts(
    Id contractHistoryId,
    List<InvoiceCanonicalService.LineAmountEdit> edits,
    String expectedContentVersion,
    String businessOperationKey
  ) {
    List<Id> lineIds = lineIdsOf(edits);
    List<Id> invoiceIds = invoiceIdsOfLines(lineIds);
    Map<String, String> tokenByInvoiceId = new Map<String, String>();
    for (Id invoiceId : invoiceIds) {
      tokenByInvoiceId.put(String.valueOf(invoiceId), expectedContentVersion);
    }
    return updateInvoiceLineAmounts(
      contractHistoryId,
      edits,
      tokenByInvoiceId,
      businessOperationKey
    );
  }

  /** 仕様: Core 第7.9.7節、第7.8節。端数調整は操作キーと行ロックと版を共有する。 */
  @AuraEnabled
  public static InvoicePreviewDto updateInvoiceLineAmounts(
    Id contractHistoryId,
    List<InvoiceCanonicalService.LineAmountEdit> edits,
    Map<String, String> expectedTokenByInvoiceId,
    String businessOperationKey
  ) {
    List<Id> lineIds = lineIdsOf(edits);
    List<Id> invoiceIds = invoiceIdsOfLines(lineIds);
    Map<Id, String> tokens = new Map<Id, String>();
    for (Id invoiceId : invoiceIds) {
      String token = null;
      if (expectedTokenByInvoiceId != null) {
        token = expectedTokenByInvoiceId.get(String.valueOf(invoiceId));
      }
      tokens.put(invoiceId, token);
    }
    DraftEditPreparation prep = prepareDraftInvoiceEdit(
      contractHistoryId,
      invoiceIds,
      lineIds,
      tokens,
      businessOperationKey
    );
    if (prep.alreadyApplied) {
      ContractOperationLogService.write(
        'AdjustInvoiceAmount',
        prep.operationKey,
        'Invoice__c',
        invoiceIds.isEmpty() ? null : String.valueOf(invoiceIds[0])
      );
      return getInvoicePreview(contractHistoryId);
    }
    try {
      InvoiceCanonicalService.updateLineAmounts(edits);
      stampDraftOperationKeys(invoiceIds, prep.operationKey);
      ContractOperationLogService.write(
        'AdjustInvoiceAmount',
        prep.operationKey,
        'Invoice__c',
        invoiceIds.isEmpty() ? null : String.valueOf(invoiceIds[0])
      );
    } catch (Exception ex) {
      throw toAuraHandled(ex.getMessage());
    }
    return getInvoicePreview(contractHistoryId);
  }

  /**
   * 検収終了日だけを更新する。確定済み請求でも通す（金額・請求日には触れない）。
   * 検収は請求確定より後にずれ込むため、確定取消を強制しない。
   * 仕様: Core 第7.6節、第7.9.6節、日付仕様 第6.1節・第7.3節。
   * 取消基準日の null 固定 overload は持たない（CHANGE-216／CHANGE-166）。
   */
  public static InvoicePreviewDto updateInvoiceLineAcceptanceEndDate(
    Id contractHistoryId,
    Id lineId,
    Date acceptanceEndDate,
    String expectedContentVersion,
    Date cancellationDate
  ) {
    return updateInvoiceLineAcceptanceEndDate(
      contractHistoryId,
      lineId,
      acceptanceEndDate,
      expectedContentVersion,
      cancellationDate,
      null
    );
  }

  /**
   * 検収終了日だけを更新する。確定済み請求でも通す（金額・請求日には触れない）。
   * 検収は請求確定より後にずれ込むため、確定取消を強制しない。
   * 仕様: Core 第7.6節・第7.7.3節・第7.9.6節・第7.9.7節、日付仕様 第6.1節・第7.3節。
   * 権限は InvoiceCanonicalService.loadAcceptanceLines → assertCanEditInvoicePreview。
   */
  @AuraEnabled
  public static InvoicePreviewDto updateInvoiceLineAcceptanceEndDate(
    Id contractHistoryId,
    Id lineId,
    Date acceptanceEndDate,
    String expectedContentVersion,
    Date cancellationDate,
    String businessOperationKey
  ) {
    assertAcceptanceLineInPreviewScope(contractHistoryId, lineId);
    try {
      InvoiceCanonicalService.updateLineAcceptanceEndDates(
        new Map<Id, Date>{ lineId => acceptanceEndDate },
        cancellationDate,
        businessOperationKey,
        expectedContentVersion
      );
      List<InvoiceLine__c> lines = [
        SELECT Invoice__c
        FROM InvoiceLine__c
        WHERE Id = :lineId
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      ContractOperationLogService.write(
        'ChangeAcceptanceEndDate',
        businessOperationKey,
        'Invoice__c',
        lines.isEmpty() ? null : String.valueOf(lines[0].Invoice__c)
      );
    } catch (Exception ex) {
      throw toAuraHandled(ex.getMessage());
    }
    return getInvoicePreview(contractHistoryId);
  }

  /** 仕様: Core 第7.7.3節、第7.6節、第7.9.6節、Accounting 第8.5節・第8.8節、日付仕様 第7.3節 */
  @AuraEnabled
  public static AccountingDiffService.CancelPreview previewInvoiceLineAcceptanceEndDate(
    Id lineId,
    Date acceptanceEndDate,
    Date cancellationDate,
    Id contractHistoryId
  ) {
    assertAcceptanceLineInPreviewScope(contractHistoryId, lineId);
    return previewInvoiceLineAcceptanceEndDate(
      lineId,
      acceptanceEndDate,
      cancellationDate
    );
  }

  /** 仕様: Core 第7.6節、第7.9.6節、Accounting 第8.5節・第8.8節、日付仕様 第7.3節 */
  public static AccountingDiffService.CancelPreview previewInvoiceLineAcceptanceEndDate(
    Id lineId,
    Date acceptanceEndDate,
    Date cancellationDate
  ) {
    if (lineId == null) {
      throw toAuraHandled('明細は必須です。');
    }
    try {
      return InvoiceCanonicalService.previewLineAcceptanceEndDates(
        new Map<Id, Date>{ lineId => acceptanceEndDate },
        cancellationDate
      );
    } catch (Exception ex) {
      throw toAuraHandled(ex.getMessage());
    }
  }

  /** 仕様: Core 第7.8節、第7.9.7節。比較値未指定は拒否する。現在版で埋めない。 */
  public static InvoicePreviewDto updateInvoiceHeaderAndDates(
    Id contractHistoryId,
    Id invoiceId,
    Date invoiceDate,
    Date paymentScheduledDate,
    String billingAddressee,
    String billingEmailTo,
    String billingEmailCc,
    String billingEmailBcc,
    Decimal taxPercent,
    String expectedContentVersion
  ) {
    return updateInvoiceHeaderAndDates(
      contractHistoryId,
      invoiceId,
      invoiceDate,
      paymentScheduledDate,
      billingAddressee,
      billingEmailTo,
      billingEmailCc,
      billingEmailBcc,
      taxPercent,
      expectedContentVersion,
      null,
      null
    );
  }

  /** 仕様: Core 第7.8節、第7.9.7節、第11.4.4節。請求情報編集は操作キーと行ロックと版を共有する。 */
  @AuraEnabled
  public static InvoicePreviewDto updateInvoiceHeaderAndDates(
    Id contractHistoryId,
    Id invoiceId,
    Date invoiceDate,
    Date paymentScheduledDate,
    String billingAddressee,
    String billingEmailTo,
    String billingEmailCc,
    String billingEmailBcc,
    Decimal taxPercent,
    String expectedContentVersion,
    String businessOperationKey,
    Map<String, Object> extraFieldValues
  ) {
    List<Id> invoiceIds = new List<Id>{ invoiceId };
    DraftEditPreparation prep = prepareDraftInvoiceEdit(
      contractHistoryId,
      invoiceIds,
      null,
      tokensForSingleOrShared(invoiceIds, expectedContentVersion),
      businessOperationKey
    );
    if (prep.alreadyApplied) {
      ContractOperationLogService.write(
        'EditInvoice',
        prep.operationKey,
        'Invoice__c',
        String.valueOf(invoiceId)
      );
      return getInvoicePreview(contractHistoryId);
    }
    try {
      InvoiceCanonicalService.updateInvoiceHeaderAndDates(
        invoiceId,
        invoiceDate,
        paymentScheduledDate,
        null,
        billingAddressee,
        billingEmailTo,
        billingEmailCc,
        billingEmailBcc,
        null,
        taxPercent,
        extraFieldValues
      );
      stampDraftOperationKeys(invoiceIds, prep.operationKey);
      ContractOperationLogService.write(
        'EditInvoice',
        prep.operationKey,
        'Invoice__c',
        String.valueOf(invoiceId)
      );
    } catch (Exception ex) {
      throw toAuraHandled(ex.getMessage());
    }
    return getInvoicePreview(contractHistoryId);
  }

  /** 仕様: Core 第7.8節、第7.9.7節 */
  public static InvoicePreviewDto applyBillingAccountContent(
    Id contractHistoryId,
    Id invoiceId,
    String expectedContentVersion
  ) {
    return applyBillingAccountContent(
      contractHistoryId,
      invoiceId,
      expectedContentVersion,
      null
    );
  }

  /** 仕様: Core 第7.8節、第7.9.7節。請求アカウントの内容を反映は操作キーと行ロックと版を共有する。 */
  @AuraEnabled
  public static InvoicePreviewDto applyBillingAccountContent(
    Id contractHistoryId,
    Id invoiceId,
    String expectedContentVersion,
    String businessOperationKey
  ) {
    List<Id> invoiceIds = new List<Id>{ invoiceId };
    DraftEditPreparation prep = prepareDraftInvoiceEdit(
      contractHistoryId,
      invoiceIds,
      null,
      tokensForSingleOrShared(invoiceIds, expectedContentVersion),
      businessOperationKey
    );
    if (prep.alreadyApplied) {
      ContractOperationLogService.write(
        'ApplyBillingAccount',
        prep.operationKey,
        'Invoice__c',
        String.valueOf(invoiceId)
      );
      return getInvoicePreview(contractHistoryId);
    }
    try {
      InvoiceCanonicalService.applyBillingAccountContent(invoiceId);
      stampDraftOperationKeys(invoiceIds, prep.operationKey);
      ContractOperationLogService.write(
        'ApplyBillingAccount',
        prep.operationKey,
        'Invoice__c',
        String.valueOf(invoiceId)
      );
    } catch (Exception ex) {
      throw toAuraHandled(ex.getMessage());
    }
    return getInvoicePreview(contractHistoryId);
  }

  /** 仕様: Core 第7.8節、第7.9.7節。比較値未指定は拒否する。現在版で埋めない。 */
  public static InvoicePreviewDto splitInvoiceByDate(
    Id contractHistoryId,
    Id sourceInvoiceId,
    Date newInvoiceDate,
    Date newPaymentScheduledDate,
    List<InvoiceCanonicalService.SplitLineInput> splitLines,
    String expectedContentVersion
  ) {
    return splitInvoiceByDate(
      contractHistoryId,
      sourceInvoiceId,
      newInvoiceDate,
      newPaymentScheduledDate,
      splitLines,
      expectedContentVersion,
      null
    );
  }

  /** 仕様: Core 第7.8節、第7.9.7節。新しい請求へ分けるときは元だけをロックする。 */
  @AuraEnabled
  public static InvoicePreviewDto splitInvoiceByDate(
    Id contractHistoryId,
    Id sourceInvoiceId,
    Date newInvoiceDate,
    Date newPaymentScheduledDate,
    List<InvoiceCanonicalService.SplitLineInput> splitLines,
    String expectedContentVersion,
    String businessOperationKey
  ) {
    List<Id> invoiceIds = new List<Id>{ sourceInvoiceId };
    DraftEditPreparation prep = prepareDraftInvoiceEdit(
      contractHistoryId,
      invoiceIds,
      lineIdsOf(splitLines),
      tokensForSingleOrShared(invoiceIds, expectedContentVersion),
      businessOperationKey
    );
    if (prep.alreadyApplied) {
      ContractOperationLogService.write(
        'SplitToNewInvoice',
        prep.operationKey,
        'Invoice__c',
        String.valueOf(sourceInvoiceId)
      );
      return getInvoicePreview(contractHistoryId);
    }
    try {
      Id createdId = InvoiceCanonicalService.splitInvoiceByDate(
        sourceInvoiceId,
        newInvoiceDate,
        newPaymentScheduledDate,
        splitLines
      );
      stampDraftOperationKeysAfterSplit(
        sourceInvoiceId,
        createdId,
        prep.operationKey
      );
      ContractOperationLogService.write(
        'SplitToNewInvoice',
        prep.operationKey,
        'Invoice__c',
        String.valueOf(sourceInvoiceId)
      );
    } catch (Exception ex) {
      throw toAuraHandled(ex.getMessage());
    }
    return getInvoicePreview(contractHistoryId);
  }

  /** 仕様: Core 第7.8節、第7.9.7節。比較値未指定は拒否する。現在版で埋めない。 */
  public static InvoicePreviewDto splitInvoiceByBillingAccount(
    Id contractHistoryId,
    Id sourceInvoiceId,
    Id newBillingAccountId,
    Date newInvoiceDate,
    Date newPaymentScheduledDate,
    List<InvoiceCanonicalService.SplitLineInput> splitLines,
    String expectedContentVersion
  ) {
    return splitInvoiceByBillingAccount(
      contractHistoryId,
      sourceInvoiceId,
      newBillingAccountId,
      newInvoiceDate,
      newPaymentScheduledDate,
      splitLines,
      expectedContentVersion,
      null
    );
  }

  /** 仕様: Core 第7.8節、第7.9.7節。新しい請求へ分けるときは元だけをロックする。 */
  @AuraEnabled
  public static InvoicePreviewDto splitInvoiceByBillingAccount(
    Id contractHistoryId,
    Id sourceInvoiceId,
    Id newBillingAccountId,
    Date newInvoiceDate,
    Date newPaymentScheduledDate,
    List<InvoiceCanonicalService.SplitLineInput> splitLines,
    String expectedContentVersion,
    String businessOperationKey
  ) {
    List<Id> invoiceIds = new List<Id>{ sourceInvoiceId };
    DraftEditPreparation prep = prepareDraftInvoiceEdit(
      contractHistoryId,
      invoiceIds,
      lineIdsOf(splitLines),
      tokensForSingleOrShared(invoiceIds, expectedContentVersion),
      businessOperationKey
    );
    if (prep.alreadyApplied) {
      ContractOperationLogService.write(
        'SplitToNewInvoice',
        prep.operationKey,
        'Invoice__c',
        String.valueOf(sourceInvoiceId)
      );
      return getInvoicePreview(contractHistoryId);
    }
    try {
      Id createdId = InvoiceCanonicalService.splitInvoiceByBillingAccount(
        sourceInvoiceId,
        newBillingAccountId,
        newInvoiceDate,
        newPaymentScheduledDate,
        splitLines
      );
      stampDraftOperationKeysAfterSplit(
        sourceInvoiceId,
        createdId,
        prep.operationKey
      );
      ContractOperationLogService.write(
        'SplitToNewInvoice',
        prep.operationKey,
        'Invoice__c',
        String.valueOf(sourceInvoiceId)
      );
    } catch (Exception ex) {
      throw toAuraHandled(ex.getMessage());
    }
    return getInvoicePreview(contractHistoryId);
  }


  /** 仕様: Core 第7.8節、第7.9.7節。比較値未指定は拒否する。現在版で埋めない。 */
  public static InvoicePreviewDto moveLinesToExistingInvoice(
    Id contractHistoryId,
    Id sourceInvoiceId,
    Id targetInvoiceId,
    List<Id> lineIds,
    String expectedContentVersion
  ) {
    return moveLinesToExistingInvoice(
      contractHistoryId,
      sourceInvoiceId,
      targetInvoiceId,
      lineIds,
      expectedContentVersion,
      expectedContentVersion,
      null
    );
  }

  /** 仕様: Core 第7.8節、第7.9.7節。既存の未確定へ移すときは元と先の両方をロックする。 */
  @AuraEnabled
  public static InvoicePreviewDto moveLinesToExistingInvoice(
    Id contractHistoryId,
    Id sourceInvoiceId,
    Id targetInvoiceId,
    List<Id> lineIds,
    String expectedContentVersion,
    String expectedTargetContentVersion,
    String businessOperationKey
  ) {
    List<Id> invoiceIds = new List<Id>{ sourceInvoiceId, targetInvoiceId };
    Map<Id, String> tokens = new Map<Id, String>();
    tokens.put(sourceInvoiceId, expectedContentVersion);
    tokens.put(targetInvoiceId, expectedTargetContentVersion);
    DraftEditPreparation prep = prepareDraftInvoiceEdit(
      contractHistoryId,
      invoiceIds,
      lineIds,
      tokens,
      businessOperationKey
    );
    if (prep.alreadyApplied) {
      ContractOperationLogService.write(
        'MoveToExistingInvoice',
        prep.operationKey,
        'Invoice__c',
        String.valueOf(sourceInvoiceId)
      );
      return getInvoicePreview(contractHistoryId);
    }
    try {
      InvoiceCanonicalService.moveLinesToExistingInvoice(
        sourceInvoiceId,
        targetInvoiceId,
        lineIds
      );
      stampDraftOperationKeysAfterSplit(
        sourceInvoiceId,
        targetInvoiceId,
        prep.operationKey
      );
      ContractOperationLogService.write(
        'MoveToExistingInvoice',
        prep.operationKey,
        'Invoice__c',
        String.valueOf(sourceInvoiceId)
      );
    } catch (Exception ex) {
      throw toAuraHandled(ex.getMessage());
    }
    return getInvoicePreview(contractHistoryId);
  }


  /** 仕様: Core 第7.8節、第7.9.7節。比較値未指定は拒否する。現在版で埋めない。 */
  public static InvoicePreviewDto splitLinesInPlace(
    Id contractHistoryId,
    Id invoiceId,
    List<InvoiceCanonicalService.SplitLineInput> splitLines,
    String expectedContentVersion
  ) {
    return splitLinesInPlace(
      contractHistoryId,
      invoiceId,
      splitLines,
      expectedContentVersion,
      null
    );
  }

  /** 仕様: Core 第7.8節、第7.9.7節。同一請求内分割は操作キーと行ロックと版を共有する。 */
  @AuraEnabled
  public static InvoicePreviewDto splitLinesInPlace(
    Id contractHistoryId,
    Id invoiceId,
    List<InvoiceCanonicalService.SplitLineInput> splitLines,
    String expectedContentVersion,
    String businessOperationKey
  ) {
    List<Id> invoiceIds = new List<Id>{ invoiceId };
    DraftEditPreparation prep = prepareDraftInvoiceEdit(
      contractHistoryId,
      invoiceIds,
      lineIdsOf(splitLines),
      tokensForSingleOrShared(invoiceIds, expectedContentVersion),
      businessOperationKey
    );
    if (prep.alreadyApplied) {
      ContractOperationLogService.write(
        'SplitLinesInPlace',
        prep.operationKey,
        'Invoice__c',
        String.valueOf(invoiceId)
      );
      return getInvoicePreview(contractHistoryId);
    }
    try {
      InvoiceCanonicalService.splitLinesInPlace(invoiceId, splitLines);
      stampDraftOperationKeys(invoiceIds, prep.operationKey);
      ContractOperationLogService.write(
        'SplitLinesInPlace',
        prep.operationKey,
        'Invoice__c',
        String.valueOf(invoiceId)
      );
    } catch (Exception ex) {
      throw toAuraHandled(ex.getMessage());
    }
    return getInvoicePreview(contractHistoryId);
  }

  /**
   * 同一請求内月分割のしきい日候補（継続課金・2か月以上の明細のみ）。
   */
  @AuraEnabled
  public static List<InvoiceCanonicalService.SplitThresholdLineOptions> getSplitThresholdDateOptions(
    Id invoiceId
  ) {
    ContractPermissionUtil.assertViewInvoicePreview();
    try {
      return InvoiceCanonicalService.getSplitThresholdDateOptions(invoiceId);
    } catch (Exception ex) {
      throw toAuraHandled(ex.getMessage());
    }
  }

  public static final String PREVIEW_SCOPE_MISMATCH_MESSAGE = '指定された請求／請求明細が、開いている契約サービスに属していません。画面を開き直してください。';

  /** 仕様: Core 第7.7.3節、第7.6節 */
  private static void assertAcceptanceLineInPreviewScope(
    Id contractHistoryId,
    Id lineId
  ) {
    if (lineId == null) {
      throw toAuraHandled('明細は必須です。');
    }
    List<InvoiceLine__c> lines = [
      SELECT Invoice__c
      FROM InvoiceLine__c
      WHERE Id = :lineId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (lines.isEmpty()) {
      throw toAuraHandled(PREVIEW_SCOPE_MISMATCH_MESSAGE);
    }
    Id invoiceId = lines[0].Invoice__c;
    Id contractServiceId = resolveContractServiceId(contractHistoryId);
    if (contractServiceId == null) {
      throw toAuraHandled(PREVIEW_SCOPE_MISMATCH_MESSAGE);
    }
    Integer inScopeInvoices = [
      SELECT COUNT()
      FROM Invoice__c
      WHERE Id = :invoiceId AND ContractService__c = :contractServiceId
      WITH SYSTEM_MODE
    ];
    if (inScopeInvoices != 1) {
      throw toAuraHandled(PREVIEW_SCOPE_MISMATCH_MESSAGE);
    }
  }

  public static final String RESET_POST_ORDER_NON_LATEST_MESSAGE = '最新の受注 Version 以外は受注直後の請求に戻せません。';
  public static final String RESET_POST_ORDER_VERSION_REQUIRED_MESSAGE = 'Version を指定してください。';
  public static final String RESET_POST_ORDER_VERSION_NOT_FOUND_MESSAGE = '指定の Version の受注履歴が見つかりません。';
  /** 仕様: Core 第7.7.2節、第6.6節。拒否するのは有効な確定済みだけ。取消済みは妨げない。 */
  public static final String RESET_POST_ORDER_ACTIVE_CONFIRMED_MESSAGE = '有効な確定済み請求がある Version は受注直後の請求に戻せません。';
  /** @deprecated CHANGE-210。{@link #RESET_POST_ORDER_ACTIVE_CONFIRMED_MESSAGE} を使う。 */
  public static final String RESET_POST_ORDER_CONFIRMED_OR_CANCELLED_MESSAGE = RESET_POST_ORDER_ACTIVE_CONFIRMED_MESSAGE;

  /**
   * 最新 Ordered Version の請求／期間明細だけを受注直後相当へ作り直す。
   * 過去 Version は触らない。ロックがある Version は generate 側で拒否。
   * 仕様: Core 第7.7.2節、第7.9.7節。比較値未指定は拒否する。現在版で埋めない。
   */
  public static InvoicePreviewDto resetLatestVersionInvoicesToPostOrder(
    Id contractHistoryId,
    String versionValue,
    String expectedContentVersion
  ) {
    try {
      Id targetHistoryId = resolveLatestOrderedHistoryIdForReset(
        contractHistoryId,
        versionValue
      );
      List<Id> draftInvoiceIds = draftInvoiceIdsOfHistory(targetHistoryId);
      Map<String, String> tokenByInvoiceId = new Map<String, String>();
      for (Id invoiceId : draftInvoiceIds) {
        tokenByInvoiceId.put(String.valueOf(invoiceId), expectedContentVersion);
      }
      return resetLatestVersionInvoicesToPostOrder(
        contractHistoryId,
        versionValue,
        tokenByInvoiceId,
        null
      );
    } catch (Exception ex) {
      throw toAuraHandled(ex.getMessage());
    }
  }

  /**
   * 最新 Ordered Version の請求／期間明細だけを受注直後相当へ作り直す。
   * 仕様: Core 第7.7.2節、第7.9.7節。当該Versionの未確定請求をすべて行ロックする。
   */
  @AuraEnabled
  public static InvoicePreviewDto resetLatestVersionInvoicesToPostOrder(
    Id contractHistoryId,
    String versionValue,
    Map<String, String> expectedTokenByInvoiceId,
    String businessOperationKey
  ) {
    try {
      InvoiceCanonicalService.assertCanEditInvoicePreview();
      Id targetHistoryId = resolveLatestOrderedHistoryIdForReset(
        contractHistoryId,
        versionValue
      );
      // 仕様: Core 第7.7.2節、第6.6節。有効確定が0件なら取消済みがあっても可。
      assertLatestVersionHasNoActiveConfirmed(targetHistoryId);
      List<Id> draftInvoiceIds = draftInvoiceIdsOfHistory(targetHistoryId);
      Map<Id, String> tokens = new Map<Id, String>();
      for (Id invoiceId : draftInvoiceIds) {
        String token = null;
        if (expectedTokenByInvoiceId != null) {
          token = expectedTokenByInvoiceId.get(String.valueOf(invoiceId));
        }
        tokens.put(invoiceId, token);
      }
      // 仕様: Core 第7.7.2節・第7.9.7節。行ロックと版比較は当該Versionの未確定だけ。
      DraftEditPreparation prep;
      if (draftInvoiceIds.isEmpty()) {
        prep = prepareResetPostOrderWithoutDrafts(
          contractHistoryId,
          businessOperationKey
        );
      } else {
        prep = prepareDraftInvoiceEdit(
          contractHistoryId,
          draftInvoiceIds,
          null,
          tokens,
          businessOperationKey
        );
      }
      if (prep.alreadyApplied) {
        ContractOperationLogService.write(
          'ResetInvoicesToPostOrder',
          prep.operationKey,
          'ContractHistory__c',
          String.valueOf(targetHistoryId)
        );
        return getInvoicePreview(contractHistoryId);
      }
      InvoiceProductGenerationService.generateForHistories(
        new Set<Id>{ targetHistoryId }
      );
      stampDraftOperationKeys(
        draftInvoiceIdsOfHistory(targetHistoryId),
        prep.operationKey
      );
      ContractOperationLogService.write(
        'ResetInvoicesToPostOrder',
        prep.operationKey,
        'ContractHistory__c',
        String.valueOf(targetHistoryId)
      );
    } catch (Exception ex) {
      throw toAuraHandled(ex.getMessage());
    }
    return getInvoicePreview(contractHistoryId);
  }

  @TestVisible
  private static Id resolveLatestOrderedHistoryIdForReset(
    Id contractHistoryId,
    String versionValue
  ) {
    if (String.isBlank(versionValue)) {
      throw new IllegalArgumentException(
        RESET_POST_ORDER_VERSION_REQUIRED_MESSAGE
      );
    }
    Decimal versionNumber;
    try {
      versionNumber = Decimal.valueOf(versionValue.trim());
    } catch (Exception ex) {
      throw new IllegalArgumentException(
        RESET_POST_ORDER_VERSION_NOT_FOUND_MESSAGE
      );
    }

    Id contractServiceId = resolveContractServiceId(contractHistoryId);
    if (contractServiceId == null) {
      throw new IllegalArgumentException(
        RESET_POST_ORDER_VERSION_NOT_FOUND_MESSAGE
      );
    }

    List<ContractHistory__c> histories = [
      SELECT Id, Version__c
      FROM ContractHistory__c
      WHERE
        ContractService__c = :contractServiceId
        AND historystatus__c = :HISTORY_STATUS_ORDERED
        AND Version__c = :versionNumber
      WITH SYSTEM_MODE
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    if (histories.isEmpty()) {
      throw new IllegalArgumentException(
        RESET_POST_ORDER_VERSION_NOT_FOUND_MESSAGE
      );
    }

    Id targetHistoryId = histories[0].Id;
    if (!EstimateRevertInvoiceService.isLatestOrderedHistory(targetHistoryId)) {
      throw new IllegalArgumentException(RESET_POST_ORDER_NON_LATEST_MESSAGE);
    }
    return targetHistoryId;
  }

  // 業務データはクライアントキャッシュ禁止（請求プレビュー表示は常に最新）
  @AuraEnabled
  public static List<BillingAccountOptionDto> getBillingAccountOptionsForPreview(
    Id contractHistoryId
  ) {
    ContractPermissionUtil.assertViewInvoicePreview();
    Id accountId = null;
    for (ContractHistory__c history : [
      SELECT ContractService__r.Account__c
      FROM ContractHistory__c
      WHERE Id = :contractHistoryId
      WITH SYSTEM_MODE
      LIMIT 1
    ]) {
      accountId = history.ContractService__r == null
        ? null
        : history.ContractService__r.Account__c;
    }
    List<BillingAccountOptionDto> options = new List<BillingAccountOptionDto>();
    if (accountId == null) {
      return options;
    }
    for (BillingAccount__c ba : [
      SELECT Id, Name
      FROM BillingAccount__c
      WHERE Account__c = :accountId
      WITH SYSTEM_MODE
      ORDER BY Name
      LIMIT 200
    ]) {
      BillingAccountOptionDto option = new BillingAccountOptionDto();
      option.id = ba.Id;
      option.name = ba.Name;
      options.add(option);
    }
    return options;
  }

  public class BillingAccountOptionDto {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
  }

  // 仕様: Core 第5.3節、第7.8.3節。消すのは未確定。取消済みの手直しでは警告しない。
  @AuraEnabled
  public static Boolean hasManualInvoiceAdjustment(Id contractHistoryId) {
    if (contractHistoryId == null) {
      return false;
    }
    Integer count = [
      SELECT COUNT()
      FROM Invoice__c
      WHERE
        ContractHistory__c = :contractHistoryId
        AND IsManuallyAdjusted__c = TRUE
        AND InvoiceTransactionStatus__c = :InvoiceTransactionStatusService.TX_DRAFT
      WITH SYSTEM_MODE
    ];
    return count > 0;
  }

  private static List<VersionOptionDto> loadOrderedVersionOptions(
    Id contractServiceId
  ) {
    List<VersionOptionDto> options = new List<VersionOptionDto>();
    if (contractServiceId == null) {
      return options;
    }

    List<ContractHistory__c> histories = [
      SELECT Version__c
      FROM ContractHistory__c
      WHERE
        ContractService__c = :contractServiceId
        AND historystatus__c = :HISTORY_STATUS_ORDERED
        AND Version__c != NULL
      WITH SYSTEM_MODE
      ORDER BY Version__c ASC
    ];

    Set<Decimal> seenVersions = new Set<Decimal>();
    for (ContractHistory__c history : histories) {
      if (seenVersions.contains(history.Version__c)) {
        continue;
      }
      seenVersions.add(history.Version__c);

      VersionOptionDto option = new VersionOptionDto();
      option.version = history.Version__c;
      option.value = String.valueOf(history.Version__c.intValue());
      option.label = InvoiceProductMergeService.formatHistoryVersionLabel(
        history.Version__c
      );
      option.periodLineAmountTotal = 0;
      option.periodLineTaxInclusiveTotal = 0;
      option.invoiceAmountTotal = 0;
      option.invoiceTaxInclusiveTotal = 0;
      option.amountDifference = 0;
      option.manualAdjustmentAmount = 0;
      options.add(option);
    }
    return options;
  }

  /**
   * Version フィルタ用に、見積（DeltaAmountSum）・請求・ずれを Version 別に載せる。
   * 見積側は Ordered のみ（Archive / Estimate を混ぜない）。
   * 仕様: Core 第7.7.0節、第7.8.5節、第7.9.1節
   */
  private static void enrichVersionAmountSummaries(
    InvoicePreviewDto preview,
    Id contractServiceId
  ) {
    if (preview == null || contractServiceId == null) {
      return;
    }
    if (preview.versionOptions == null) {
      preview.versionOptions = new List<VersionOptionDto>();
    }

    Map<String, VersionOptionDto> optionByValue = new Map<String, VersionOptionDto>();
    for (VersionOptionDto option : preview.versionOptions) {
      if (option == null || String.isBlank(option.value)) {
        continue;
      }
      if (option.periodLineAmountTotal == null) {
        option.periodLineAmountTotal = 0;
      }
      if (option.periodLineTaxInclusiveTotal == null) {
        option.periodLineTaxInclusiveTotal = 0;
      }
      if (option.invoiceAmountTotal == null) {
        option.invoiceAmountTotal = 0;
      }
      if (option.invoiceTaxInclusiveTotal == null) {
        option.invoiceTaxInclusiveTotal = 0;
      }
      if (option.manualAdjustmentAmount == null) {
        option.manualAdjustmentAmount = 0;
      }
      optionByValue.put(option.value, option);
    }

    Decimal displayTaxPercent = loadServiceDisplayTaxPercent(contractServiceId);
    ScopedEstimateSummary estimateSummary = buildScopedEstimateSummary(
      contractServiceId
    );
    for (String value : estimateSummary.byVersion.keySet()) {
      VersionOptionDto option = optionByValue.get(value);
      if (option == null) {
        continue;
      }
      option.periodLineAmountTotal = estimateSummary.byVersion.get(value);
    }

    Decimal previewInvoiceIncl = 0;
    List<InvoiceGroupDto> invoices = preview.invoices == null
      ? new List<InvoiceGroupDto>()
      : preview.invoices;
    for (InvoiceGroupDto invoice : invoices) {
      if (
        invoice == null ||
        invoice.historyVersion == null ||
        invoice.isCancelled == true
      ) {
        continue;
      }
      String value = String.valueOf(invoice.historyVersion.intValue());
      VersionOptionDto option = optionByValue.get(value);
      if (option == null) {
        continue;
      }
      Decimal amount = invoice.amountTotal == null ? 0 : invoice.amountTotal;
      Decimal incl = invoice.taxInclusiveAmount == null
        ? amount
        : invoice.taxInclusiveAmount;
      option.invoiceAmountTotal =
        (option.invoiceAmountTotal == null ? 0 : option.invoiceAmountTotal) +
        amount;
      option.invoiceTaxInclusiveTotal =
        (option.invoiceTaxInclusiveTotal == null
          ? 0
          : option.invoiceTaxInclusiveTotal) + incl;
      previewInvoiceIncl += incl;
    }

    for (VersionOptionDto option : preview.versionOptions) {
      Decimal periodTotal = option.periodLineAmountTotal == null
        ? 0
        : option.periodLineAmountTotal;
      Decimal invoiceTotal = option.invoiceAmountTotal == null
        ? 0
        : option.invoiceAmountTotal;
      option.periodLineTaxInclusiveTotal = inclusiveFromExcl(
        periodTotal,
        displayTaxPercent
      );
      if (option.invoiceTaxInclusiveTotal == null) {
        option.invoiceTaxInclusiveTotal = 0;
      }
      option.amountDifference = invoiceTotal - periodTotal;
      if (option.manualAdjustmentAmount == null) {
        option.manualAdjustmentAmount = 0;
      }
    }
    preview.invoiceTaxInclusiveTotal = previewInvoiceIncl;
    preview.periodLineTaxInclusiveTotal = inclusiveFromExcl(
      preview.periodLineAmountTotal,
      displayTaxPercent
    );
  }

  private static Boolean hasOrderPermission() {
    if (Test.isRunningTest()) {
      return testHasOrderPermission;
    }
    return ContractPermissionUtil.has(ContractPermissionUtil.ORDER);
  }

  private static Boolean hasRevertPermission() {
    if (Test.isRunningTest()) {
      return testHasRevertPermission;
    }
    return ContractPermissionUtil.has(ContractPermissionUtil.REVERT);
  }

  private static void assertOrderPermission() {
    if (!hasOrderPermission()) {
      throw toAuraHandled('受注を実行する権限がありません。');
    }
  }

  private static void assertRevertPermission() {
    if (!hasRevertPermission()) {
      throw toAuraHandled('差し戻しを実行する権限がありません。');
    }
  }

  private static String buildRevertBlockedReason(
    Id contractHistoryId,
    String historyStatus
  ) {
    if (historyStatus != HISTORY_STATUS_ORDERED) {
      return '受注済み状態の契約履歴のみ差し戻しできます。';
    }
    String lockedReason = buildLockedRevertBlockedReason(contractHistoryId);
    if (String.isNotBlank(lockedReason)) {
      return lockedReason;
    }
    if (
      !EstimateRevertInvoiceService.isLatestOrderedHistory(contractHistoryId)
    ) {
      return EstimateRevertInvoiceService.NON_LATEST_ORDERED_REVERT_MESSAGE;
    }
    return null;
  }

  private static String buildLockedRevertBlockedReason(Id contractHistoryId) {
    if (contractHistoryId == null) {
      return null;
    }
    Set<Id> historyIds = new Set<Id>{ contractHistoryId };
    if (InvoiceLockUtil.hasLockedInvoices(historyIds)) {
      return InvoiceLockUtil.LOCKED_HISTORY_BLOCK_MESSAGE;
    }
    return null;
  }

  private static String extractDmlMessage(DmlException ex) {
    if (ex == null) {
      return '差し戻し処理中にエラーが発生しました。';
    }
    if (ex.getNumDml() > 0) {
      return ex.getDmlMessage(0);
    }
    return String.isNotBlank(ex.getMessage())
      ? ex.getMessage()
      : '差し戻し処理中にエラーが発生しました。';
  }

  private static ContractHistory__c loadOrderedHistory(Id contractHistoryId) {
    if (contractHistoryId == null) {
      throw toAuraHandled('契約履歴IDが指定されていません。');
    }

    List<ContractHistory__c> histories = [
      SELECT Id, historystatus__c, ContractService__c, LastModifiedDate
      FROM ContractHistory__c
      WHERE Id = :contractHistoryId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (histories.isEmpty()) {
      throw toAuraHandled('契約履歴が見つかりません。');
    }
    ContractHistory__c history = histories[0];
    if (history.historystatus__c != HISTORY_STATUS_ORDERED) {
      throw toAuraHandled(
        '受注済み状態の契約履歴のみ差し戻しできます。'
      );
    }
    return history;
  }

  private static ContractHistory__c loadEstimateHistory(Id contractHistoryId) {
    if (contractHistoryId == null) {
      throw toAuraHandled('契約履歴IDが指定されていません。');
    }

    List<ContractHistory__c> histories = queryEstimateHistoryForEdit(
      contractHistoryId
    );
    if (histories.isEmpty()) {
      throw toAuraHandled('契約履歴が見つかりません。');
    }
    ContractHistory__c history = histories[0];
    if (history.historystatus__c != HISTORY_STATUS_ESTIMATE) {
      throw toAuraHandled('見積状態の契約履歴のみ編集できます。');
    }
    return history;
  }

  private static ContractHistory__c loadEstimateHistoryForOrder(
    Id contractHistoryId,
    Boolean failAsConflict
  ) {
    if (contractHistoryId == null) {
      throw toAuraHandled('契約履歴IDが指定されていません。');
    }
    List<ContractHistory__c> histories = queryEstimateHistoryForEdit(
      contractHistoryId,
      true
    );
    if (histories.isEmpty()) {
      throw toAuraHandled('契約履歴が見つかりません。');
    }
    ContractHistory__c history = histories[0];
    if (history.historystatus__c != HISTORY_STATUS_ESTIMATE) {
      if (failAsConflict) {
        throw ContractOptimisticLockUtil.conflict('契約履歴');
      }
      throw toAuraHandled('見積状態の契約履歴のみ編集できます。');
    }
    return history;
  }

  private static void validateReadyForOrder(ContractHistory__c history) {
    // 正はトリガ側。コントローラは UX 用の事前チェック（同一サービス）。
    ContractOrderValidationService.assertReadyForOrder(history);
  }

  private static Id resolveBillingAccountId(Id contractServiceId) {
    if (contractServiceId == null) {
      return null;
    }
    List<ContractService__c> services = [
      SELECT BiilingAcccount__c
      FROM ContractService__c
      WHERE Id = :contractServiceId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return services.isEmpty() ? null : services[0].BiilingAcccount__c;
  }

  private static Id resolveContractServiceId(Id contractHistoryId) {
    ContractHistory__c history = resolveHistoryForPreview(contractHistoryId);
    return history == null ? null : history.ContractService__c;
  }

  private static List<Invoice__c> previewInvoicesForIntegrity(
    InvoicePreviewDto preview
  ) {
    Set<Id> invoiceIds = new Set<Id>();
    if (preview != null && preview.invoices != null) {
      for (InvoiceGroupDto invoiceGroup : preview.invoices) {
        if (invoiceGroup != null && invoiceGroup.invoiceId != null) {
          invoiceIds.add(invoiceGroup.invoiceId);
        }
      }
    }
    if (invoiceIds.isEmpty()) {
      return new List<Invoice__c>();
    }
    return [
      SELECT Id, ContractHistory__c
      FROM Invoice__c
      WHERE Id IN :invoiceIds
      WITH SYSTEM_MODE
    ];
  }

  /** 仕様: Core 第7.7.3節、第7.9.3節、第7.9.6節 */
  @AuraEnabled
  public static AccountingDiffService.CancelPreview previewCancelConfirmed(
    Id invoiceId,
    Date cancellationDate,
    Id contractHistoryId
  ) {
    if (contractHistoryId == null || invoiceId == null) {
      throw toAuraHandled(PREVIEW_SCOPE_MISMATCH_MESSAGE);
    }
    InvoiceOpsController.assertInvoicesInScope(
      contractHistoryId,
      new List<Id>{ invoiceId }
    );
    return previewCancelConfirmed(invoiceId, cancellationDate);
  }

  /** 仕様: Core 第7.9.3節 */
  public static AccountingDiffService.CancelPreview previewCancelConfirmed(
    Id invoiceId,
    Date cancellationDate
  ) {
    try {
      return InvoiceCancelService.previewConfirmed(invoiceId, cancellationDate);
    } catch (Exception ex) {
      throw toAuraHandled(ex.getMessage());
    }
  }

  public static InvoicePreviewDto cancelConfirmedFromPreview(
    Id contractHistoryId,
    Id invoiceId,
    String cancellationReason,
    String cancellationReasonText,
    Date cancellationDate,
    String expectedContentVersion
  ) {
    return cancelConfirmedFromPreview(
      contractHistoryId,
      invoiceId,
      cancellationReason,
      cancellationReasonText,
      cancellationDate,
      expectedContentVersion,
      null
    );
  }

  /** 仕様: Core 第7.9.3節、第7.9.7節 */
  @AuraEnabled
  public static InvoicePreviewDto cancelConfirmedFromPreview(
    Id contractHistoryId,
    Id invoiceId,
    String cancellationReason,
    String cancellationReasonText,
    Date cancellationDate,
    String expectedContentVersion,
    String businessOperationKey
  ) {
    ContractPermissionUtil.assertCancelInvoice();
    if (contractHistoryId == null || invoiceId == null) {
      throw toAuraHandled(PREVIEW_SCOPE_MISMATCH_MESSAGE);
    }
    Id contractServiceId = resolveContractServiceId(contractHistoryId);
    if (contractServiceId == null) {
      throw toAuraHandled(PREVIEW_SCOPE_MISMATCH_MESSAGE);
    }
    Integer inScopeInvoices = [
      SELECT COUNT()
      FROM Invoice__c
      WHERE Id = :invoiceId AND ContractService__c = :contractServiceId
      WITH SYSTEM_MODE
    ];
    if (inScopeInvoices != 1) {
      throw toAuraHandled(PREVIEW_SCOPE_MISMATCH_MESSAGE);
    }
    try {
      InvoiceCancelService.CancelRequest request = new InvoiceCancelService.CancelRequest();
      request.invoiceId = invoiceId;
      request.cancellationReason = cancellationReason;
      request.cancellationReasonText = cancellationReasonText;
      request.cancellationDate = cancellationDate;
      request.businessOperationKey = businessOperationKey;
      request.expectedToken = expectedContentVersion;
      InvoiceCancelService.cancelConfirmed(request);
    } catch (Exception ex) {
      throw toAuraHandled(ex.getMessage());
    }
    return getInvoicePreview(contractHistoryId);
  }

  /**
   * 仕様: Core 第7.7.2節、第6.6節、第1.1.5節。
   * 有効な確定済みが1件でもあれば拒否する。取消済みだけでは拒否しない。
   */
  private static void assertLatestVersionHasNoActiveConfirmed(Id contractHistoryId) {
    if (contractHistoryId == null) {
      return;
    }
    for (Invoice__c invoice : [
      SELECT InvoiceTransactionStatus__c
      FROM Invoice__c
      WHERE ContractHistory__c = :contractHistoryId
      WITH SYSTEM_MODE
    ]) {
      if (InvoiceTransactionStatusService.isConfirmed(invoice)) {
        throw new IllegalArgumentException(
          RESET_POST_ORDER_ACTIVE_CONFIRMED_MESSAGE
        );
      }
    }
  }

  /** @deprecated CHANGE-210。{@link #assertLatestVersionHasNoActiveConfirmed} を使う。 */
  @TestVisible
  private static void assertLatestVersionInvoicesAllDraft(Id contractHistoryId) {
    assertLatestVersionHasNoActiveConfirmed(contractHistoryId);
  }

  /**
   * 取消済みのみで未確定が無いときの受注直後戻し準備。
   * 仕様: Core 第7.7.2節、第7.9.7節。
   */
  private static DraftEditPreparation prepareResetPostOrderWithoutDrafts(
    Id contractHistoryId,
    String businessOperationKey
  ) {
    Id contractServiceId = resolveContractServiceId(contractHistoryId);
    String operationKey = AccountingCauseLockService.resolveOrIssueOperationKey(
      businessOperationKey
    );
    DraftEditPreparation prep = new DraftEditPreparation();
    prep.operationKey = operationKey;
    prep.alreadyApplied = false;
    if (String.isNotBlank(businessOperationKey) && contractServiceId != null) {
      Integer existing = [
        SELECT COUNT()
        FROM Invoice__c
        WHERE
          ContractService__c = :contractServiceId
          AND BusinessOperationKey__c = :operationKey
        WITH SYSTEM_MODE
      ];
      if (existing > 0) {
        prep.alreadyApplied = true;
      }
    }
    return prep;
  }

  private static PreviewScopeDto fillScopeFromHistory(
    PreviewScopeDto scope,
    Id historyId,
    Id invoiceId
  ) {
    List<ContractHistory__c> histories = [
      SELECT Id, ContractService__c, Version__c, historystatus__c
      FROM ContractHistory__c
      WHERE Id = :historyId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (histories.isEmpty()) {
      scope.blockReason = '契約履歴が見つかりません。';
      return scope;
    }
    ContractHistory__c history = histories[0];
    scope.contractHistoryId = history.Id;
    scope.contractServiceId = history.ContractService__c;
    scope.invoiceId = invoiceId;
    if (history.historystatus__c == ContractDomainConstants.HISTORY_STATUS_ARCHIVE) {
      scope.blockReason = 'アーカイブ済みの契約履歴では請求ボードは利用できません。';
      return scope;
    }
    if (history.historystatus__c != HISTORY_STATUS_ORDERED) {
      scope.blockReason = 'Estimate 状態の契約履歴です。「受注」ボタンをご利用ください。';
      return scope;
    }
    scope.initialVersion = history.Version__c == null
      ? null
      : String.valueOf(history.Version__c.intValue());
    scope.initialInvoiceId = invoiceId;
    scope.canOpen = true;
    return scope;
  }

  private static PreviewScopeDto fillScopeFromService(
    PreviewScopeDto scope,
    Id serviceId
  ) {
    List<ContractService__c> services = [
      SELECT Id, LatestOrderedHistory__c
      FROM ContractService__c
      WHERE Id = :serviceId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (services.isEmpty()) {
      scope.blockReason = '契約サービスが見つかりません。';
      return scope;
    }
    scope.contractServiceId = services[0].Id;
    if (services[0].LatestOrderedHistory__c == null) {
      scope.blockReason = 'Latest Ordered がない契約サービスでは請求ボードを開けません。';
      return scope;
    }
    PreviewScopeDto filled = fillScopeFromHistory(
      scope,
      services[0].LatestOrderedHistory__c,
      null
    );
    if (filled.canOpen == true) {
      filled.initialVersion = 'ALL';
      filled.initialInvoiceId = null;
    }
    return filled;
  }

  private static PreviewScopeDto fillScopeFromInvoice(
    PreviewScopeDto scope,
    Id invoiceId
  ) {
    List<Invoice__c> invoices = [
      SELECT Id, ContractHistory__c
      FROM Invoice__c
      WHERE Id = :invoiceId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (invoices.isEmpty() || invoices[0].ContractHistory__c == null) {
      scope.blockReason = '請求書の契約履歴が見つかりません。';
      return scope;
    }
    return fillScopeFromHistory(
      scope,
      invoices[0].ContractHistory__c,
      invoices[0].Id
    );
  }

  private static ContractHistory__c resolveHistoryForPreview(
    Id contractHistoryId
  ) {
    if (contractHistoryId == null) {
      return null;
    }
    List<ContractHistory__c> histories = [
      SELECT ContractService__c, Version__c
      FROM ContractHistory__c
      WHERE Id = :contractHistoryId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return histories.isEmpty() ? null : histories[0];
  }

  private static List<ProductLineDto> loadProductLines(Id contractHistoryId) {
    List<ProductLineDto> lines = new List<ProductLineDto>();
    for (ContractProduct__c product : [
      SELECT
        Product__r.Name,
        Quantity__c,
        UnitPrice__c,
        Unit__c,
        BillingType__c,
        InvoiceSetting__c,
        StartDate__c,
        Enddate__c
      FROM ContractProduct__c
      WHERE ContractHistory__c = :contractHistoryId
      WITH SYSTEM_MODE
      ORDER BY StartDate__c ASC NULLS LAST, Product__r.Name ASC
    ]) {
      ProductLineDto line = new ProductLineDto();
      line.productName = product.Product__r == null
        ? ''
        : product.Product__r.Name;
      line.quantity = product.Quantity__c;
      line.unitPrice = product.UnitPrice__c;
      line.unit = product.Unit__c;
      line.billingType = product.BillingType__c;
      line.invoiceSetting = product.InvoiceSetting__c;
      line.startDate = formatDate(product.StartDate__c);
      line.endDate = formatDate(product.Enddate__c);
      Decimal qty = product.Quantity__c == null ? 0 : product.Quantity__c;
      Decimal price = product.UnitPrice__c == null ? 0 : product.UnitPrice__c;
      line.lineAmount = qty * price;
      lines.add(line);
    }
    return lines;
  }

  private static EstimateCreateController.BillingAccountInvoiceSettingsDto buildBillingSettings(
    BillingAccount__c billingAccount
  ) {
    if (billingAccount == null) {
      return new EstimateCreateController.BillingAccountInvoiceSettingsDto();
    }
    return EstimateCreateController.getBillingAccountInvoiceSettings(
      billingAccount.Id
    );
  }

  private static List<ContractHistory__c> queryContractHistoryForOrderContext(
    Id contractHistoryId
  ) {
    return queryContractHistoryForOrderContext(contractHistoryId, false);
  }

  private static List<ContractHistory__c> queryContractHistoryForOrderContext(
    Id contractHistoryId,
    Boolean lockForUpdate
  ) {
    String editableFieldClause = buildOrderHistoryEditableFieldClause();
    String soql =
      'SELECT Id, Name, Type__c, historystatus__c, Version__c, LastModifiedDate, BusinessOperationKey__c, ' +
      'CurrentTermStartDate__c, CurrentTermEndDate__c, EffectiveDate__c, ' +
      'Opportunity__c, CreateRenewOpportunity__c' +
      editableFieldClause +
      ', ContractService__c, ContractService__r.Name, ContractService__r.Lifecycle__c, ' +
      'ContractService__r.Account__r.Name, ContractService__r.BiilingAcccount__c, ' +
      'ContractService__r.BiilingAcccount__r.Name, ' +
      'ContractService__r.BiilingAcccount__r.InvoiceDateMethod__c, ' +
      'ContractService__r.BiilingAcccount__r.InvoiceDateDayKind__c, ' +
      'ContractService__r.BiilingAcccount__r.InvoiceDateDayOfMonth__c, ' +
      'ContractService__r.BiilingAcccount__r.InvoiceDateMonthOffset__c, ' +
      'ContractService__r.BiilingAcccount__r.InvoiceDateDayOffset__c, ' +
      'ContractService__r.BiilingAcccount__r.InvoiceDateAdjust__c, ' +
      'ContractService__r.BiilingAcccount__r.PaymentTermMethod__c, ' +
      'ContractService__r.BiilingAcccount__r.PaymentTermDayKind__c, ' +
      'ContractService__r.BiilingAcccount__r.PaymentTermDayOfMonth__c, ' +
      'ContractService__r.BiilingAcccount__r.PaymentTermMonthOffset__c, ' +
      'ContractService__r.BiilingAcccount__r.PaymentTermDayOffset__c, ' +
      'ContractService__r.BiilingAcccount__r.PaymentTermAdjust__c, ' +
      'ContractService__r.BiilingAcccount__r.BillingAddressee__c, ' +
      'ContractService__r.BiilingAcccount__r.BillingEmailTo__c, ' +
      'ContractService__r.BiilingAcccount__r.BillingEmailCc__c, ' +
      'ContractService__r.BiilingAcccount__r.BillingEmailBcc__c, ' +
      'ContractService__r.BiilingAcccount__r.Account__r.Name ' +
      'FROM ContractHistory__c WHERE Id = :contractHistoryId LIMIT 1' +
      (lockForUpdate ? ' FOR UPDATE' : '');
    return Database.queryWithBinds(
      soql,
      new Map<String, Object>{ 'contractHistoryId' => contractHistoryId },
      AccessLevel.SYSTEM_MODE
    );
  }

  private static List<ContractHistory__c> queryEstimateHistoryForEdit(
    Id contractHistoryId
  ) {
    return queryEstimateHistoryForEdit(contractHistoryId, false);
  }

  private static List<ContractHistory__c> queryEstimateHistoryForEdit(
    Id contractHistoryId,
    Boolean lockForUpdate
  ) {
    String editableFieldClause = buildOrderHistoryEditableFieldClause();
    String soql =
      'SELECT Id, Type__c, historystatus__c, Version__c, ContractService__c, ' +
      'CreateRenewOpportunity__c, RenewOpportunityRequestCount__c, RenewalOpportunity__c, ' +
      'ContractService__r.Lifecycle__c, ContractService__r.Account__c, LastModifiedDate, BusinessOperationKey__c' +
      editableFieldClause +
      ' FROM ContractHistory__c WHERE Id = :contractHistoryId LIMIT 1' +
      (lockForUpdate ? ' FOR UPDATE' : '');
    return Database.queryWithBinds(
      soql,
      new Map<String, Object>{ 'contractHistoryId' => contractHistoryId },
      AccessLevel.SYSTEM_MODE
    );
  }

  /** 仕様: Core 第5.2節、第11.5節。Cancel、Spot、Lifecycle未確定かつ継続課金なしは作成要求の対象外。 */
  public static Boolean shouldSkipRenewOpportunity(
    ContractHistory__c history
  ) {
    if (history == null) {
      return true;
    }
    if (history.Type__c == HISTORY_TYPE_CANCEL) {
      return true;
    }
    String lifecycle = history.ContractService__r == null
      ? null
      : history.ContractService__r.Lifecycle__c;
    if (ContractServiceLifecycleService.isSpotLifecycle(lifecycle)) {
      return true;
    }
    if (ContractServiceLifecycleService.isTermLifecycle(lifecycle)) {
      return false;
    }
    // 初回受注前など Lifecycle 未確定: 継続課金が無ければ Spot 見込み
    return !historyHasRecurringProducts(history.Id);
  }

  private static Boolean historyHasRecurringProducts(Id contractHistoryId) {
    if (contractHistoryId == null) {
      return false;
    }
    for (ContractProduct__c product : [
      SELECT BillingType__c, Quantity__c
      FROM ContractProduct__c
      WHERE ContractHistory__c = :contractHistoryId AND Quantity__c > 0
      WITH SYSTEM_MODE
    ]) {
      String billingType = ContractMetadataService.resolveLineBillingType(
        product
      );
      if (ContractMetadataService.isRecurringBillingType(billingType)) {
        return true;
      }
    }
    return false;
  }

  private static void assertPreviewContentUnchanged(
    Id contractHistoryId,
    String expectedContentVersion
  ) {
    Id contractServiceId = resolveContractServiceId(contractHistoryId);
    ContractOptimisticLockUtil.assertRequiredUnchanged(
      resolvePreviewContentDatetime(contractServiceId),
      expectedContentVersion,
      '請求ボード'
    );
  }

  /** 仕様: Core 第7.9.7節。未確定編集の操作キー・行ロック・版比較。 */
  private class DraftEditPreparation {
    public String operationKey;
    public Boolean alreadyApplied;
  }

  private static DraftEditPreparation prepareDraftInvoiceEdit(
    Id contractHistoryId,
    List<Id> invoiceIds,
    List<Id> lineIds,
    Map<Id, String> expectedTokenByInvoiceId,
    String businessOperationKey
  ) {
    ContractPermissionUtil.assertEditDraftInvoice();
    Id contractServiceId = resolveContractServiceId(contractHistoryId);
    assertPreviewScope(
      contractServiceId,
      invoiceIds,
      lineIds
    );
    String operationKey = AccountingCauseLockService.resolveOrIssueOperationKey(
      businessOperationKey
    );
    DraftEditPreparation prep = new DraftEditPreparation();
    prep.operationKey = operationKey;
    prep.alreadyApplied = false;
    if (String.isNotBlank(businessOperationKey) && contractServiceId != null) {
      Integer existing = [
        SELECT COUNT()
        FROM Invoice__c
        WHERE
          ContractService__c = :contractServiceId
          AND BusinessOperationKey__c = :operationKey
        WITH SYSTEM_MODE
      ];
      if (existing > 0) {
        prep.alreadyApplied = true;
        return prep;
      }
    }
    Set<Id> targetInvoiceIds = compactIds(invoiceIds);
    if (targetInvoiceIds.isEmpty()) {
      throw toAuraHandled('請求は必須です。');
    }
    List<Id> lockOrder = new List<Id>(targetInvoiceIds);
    lockOrder.sort();
    for (Id invoiceId : lockOrder) {
      AccountingCauseLockService.lockInvoice(invoiceId);
    }
    for (Id invoiceId : lockOrder) {
      String expectedToken = expectedTokenByInvoiceId == null
        ? null
        : expectedTokenByInvoiceId.get(invoiceId);
      AccountingCauseLockService.assertInvoiceOperationUnchanged(
        invoiceId,
        expectedToken
      );
    }
    return prep;
  }

  private static void assertPreviewScope(
    Id contractServiceId,
    List<Id> invoiceIds,
    List<Id> lineIds
  ) {
    Set<Id> targetInvoiceIds = compactIds(invoiceIds);
    Set<Id> targetLineIds = compactIds(lineIds);
    if (targetInvoiceIds.isEmpty() && targetLineIds.isEmpty()) {
      return;
    }
    if (contractServiceId == null) {
      throw toAuraHandled(PREVIEW_SCOPE_MISMATCH_MESSAGE);
    }
    if (!targetInvoiceIds.isEmpty()) {
      Integer inScopeInvoices = [
        SELECT COUNT()
        FROM Invoice__c
        WHERE
          Id IN :targetInvoiceIds
          AND ContractService__c = :contractServiceId
        WITH SYSTEM_MODE
      ];
      if (inScopeInvoices != targetInvoiceIds.size()) {
        throw toAuraHandled(PREVIEW_SCOPE_MISMATCH_MESSAGE);
      }
    }
    if (!targetLineIds.isEmpty()) {
      Integer inScopeLines = [
        SELECT COUNT()
        FROM InvoiceLine__c
        WHERE
          Id IN :targetLineIds
          AND Invoice__r.ContractService__c = :contractServiceId
        WITH SYSTEM_MODE
      ];
      if (inScopeLines != targetLineIds.size()) {
        throw toAuraHandled(PREVIEW_SCOPE_MISMATCH_MESSAGE);
      }
    }
  }

  private static void stampDraftOperationKeys(
    List<Id> invoiceIds,
    String operationKey
  ) {
    if (String.isBlank(operationKey)) {
      return;
    }
    Set<Id> ids = compactIds(invoiceIds);
    if (ids.isEmpty()) {
      return;
    }
    List<Invoice__c> updates = new List<Invoice__c>();
    for (Id invoiceId : ids) {
      updates.add(
        new Invoice__c(Id = invoiceId, BusinessOperationKey__c = operationKey)
      );
    }
    Boolean previousLock = InvoiceLockUtil.allowLockedStatusWrite;
    InvoiceLockUtil.allowLockedStatusWrite = true;
    try {
      SystemContextAccess.updateRecords(updates);
    } finally {
      InvoiceLockUtil.allowLockedStatusWrite = previousLock;
    }
  }

  private static void stampDraftOperationKeysAfterSplit(
    Id sourceInvoiceId,
    Id createdOrTargetInvoiceId,
    String operationKey
  ) {
    List<Id> surviving = new List<Id>();
    Set<Id> candidates = new Set<Id>();
    if (sourceInvoiceId != null) {
      candidates.add(sourceInvoiceId);
    }
    if (createdOrTargetInvoiceId != null) {
      candidates.add(createdOrTargetInvoiceId);
    }
    for (Invoice__c invoice : [
      SELECT Id
      FROM Invoice__c
      WHERE Id IN :candidates
      WITH SYSTEM_MODE
    ]) {
      surviving.add(invoice.Id);
    }
    stampDraftOperationKeys(surviving, operationKey);
  }

  private static List<Id> invoiceIdsOfLines(List<Id> lineIds) {
    List<Id> invoiceIds = new List<Id>();
    Set<Id> lineIdSet = compactIds(lineIds);
    if (lineIdSet.isEmpty()) {
      return invoiceIds;
    }
    for (InvoiceLine__c line : [
      SELECT Invoice__c
      FROM InvoiceLine__c
      WHERE Id IN :lineIdSet
      WITH SYSTEM_MODE
    ]) {
      if (line.Invoice__c != null) {
        invoiceIds.add(line.Invoice__c);
      }
    }
    return new List<Id>(compactIds(invoiceIds));
  }

  /** 仕様: Core 第7.7.2節・第7.9.7節。未確定だけ。取消済みは含めない。 */
  private static List<Id> draftInvoiceIdsOfHistory(Id contractHistoryId) {
    List<Id> invoiceIds = new List<Id>();
    if (contractHistoryId == null) {
      return invoiceIds;
    }
    for (Invoice__c invoice : [
      SELECT Id, InvoiceTransactionStatus__c
      FROM Invoice__c
      WHERE ContractHistory__c = :contractHistoryId
      WITH SYSTEM_MODE
      ORDER BY Id
    ]) {
      if (InvoiceTransactionStatusService.isDraft(invoice)) {
        invoiceIds.add(invoice.Id);
      }
    }
    return invoiceIds;
  }

  private static Map<Id, String> tokensForSingleOrShared(
    List<Id> invoiceIds,
    String expectedContentVersion
  ) {
    Map<Id, String> tokens = new Map<Id, String>();
    for (Id invoiceId : compactIds(invoiceIds)) {
      tokens.put(invoiceId, expectedContentVersion);
    }
    return tokens;
  }

  /**
   * プレビュー編集の共通前提。楽観ロックに加え、
   * 対象請求／明細が開いている契約履歴の契約サービス配下であることを確認する。
   * 画面から来た Id を無条件に信じない（他サービス・他顧客の書き換え防止）。
   */
  private static void assertPreviewRequest(
    Id contractHistoryId,
    String expectedContentVersion,
    List<Id> invoiceIds,
    List<Id> lineIds
  ) {
    Id contractServiceId = resolveContractServiceId(contractHistoryId);
    ContractOptimisticLockUtil.assertRequiredUnchanged(
      resolvePreviewContentDatetime(contractServiceId),
      expectedContentVersion,
      '請求ボード'
    );
    assertPreviewScope(contractServiceId, invoiceIds, lineIds);
  }

  private static Set<Id> compactIds(List<Id> ids) {
    Set<Id> compacted = new Set<Id>();
    if (ids == null) {
      return compacted;
    }
    for (Id value : ids) {
      if (value != null) {
        compacted.add(value);
      }
    }
    return compacted;
  }

  private static List<Id> lineIdsOf(
    List<InvoiceCanonicalService.LineAmountEdit> edits
  ) {
    List<Id> ids = new List<Id>();
    if (edits == null) {
      return ids;
    }
    for (InvoiceCanonicalService.LineAmountEdit edit : edits) {
      if (edit != null && edit.lineId != null) {
        ids.add(edit.lineId);
      }
    }
    return ids;
  }

  private static List<Id> lineIdsOf(
    List<InvoiceCanonicalService.SplitLineInput> splitLines
  ) {
    List<Id> ids = new List<Id>();
    if (splitLines == null) {
      return ids;
    }
    for (InvoiceCanonicalService.SplitLineInput splitLine : splitLines) {
      if (splitLine != null && splitLine.lineId != null) {
        ids.add(splitLine.lineId);
      }
    }
    return ids;
  }

  private static String resolvePreviewContentToken(Id contractServiceId) {
    return ContractOptimisticLockUtil.toToken(
      resolvePreviewContentDatetime(contractServiceId)
    );
  }

  private static Datetime resolvePreviewContentDatetime(Id contractServiceId) {
    if (contractServiceId == null) {
      return null;
    }
    List<AggregateResult> rows = [
      SELECT MAX(LastModifiedDate) maxLm
      FROM Invoice__c
      WHERE ContractService__c = :contractServiceId
      WITH SYSTEM_MODE
    ];
    if (rows.isEmpty()) {
      return null;
    }
    return (Datetime) rows[0].get('maxLm');
  }

  private static String buildOrderHistoryEditableFieldClause() {
    Map<String, Schema.SObjectField> fieldMap = ContractHistory__c.SObjectType.getDescribe()
      .fields.getMap();
    List<String> validatedFields = new List<String>();
    for (
      String apiName : OrderWizardFieldService.getActiveOrderHistoryFieldApiNames()
    ) {
      if (String.isNotBlank(apiName) && fieldMap.containsKey(apiName)) {
        validatedFields.add(apiName);
      }
    }
    if (validatedFields.isEmpty()) {
      return '';
    }
    return ', ' + String.join(validatedFields, ', ');
  }

  private static Map<String, Object> buildBillingCustomFields(
    BillingAccount__c billingAccount
  ) {
    Map<String, Object> values = new Map<String, Object>();
    if (billingAccount == null || billingAccount.Id == null) {
      return values;
    }

    List<BillingAccount__c> billingAccounts = [
      SELECT
        BillingAddressee__c,
        BillingEmailTo__c,
        BillingEmailCc__c,
        BillingEmailBcc__c,
        InvoiceDateMethod__c,
        InvoiceDateDayKind__c,
        InvoiceDateDayOfMonth__c,
        InvoiceDateMonthOffset__c,
        InvoiceDateDayOffset__c,
        InvoiceDateAdjust__c,
        PaymentTermMethod__c,
        PaymentTermDayKind__c,
        PaymentTermDayOfMonth__c,
        PaymentTermMonthOffset__c,
        PaymentTermDayOffset__c,
        PaymentTermAdjust__c
      FROM BillingAccount__c
      WHERE Id = :billingAccount.Id
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (billingAccounts.isEmpty()) {
      return values;
    }

    BillingAccount__c loaded = billingAccounts[0];
    values.put('BillingAddressee__c', loaded.BillingAddressee__c);
    values.put('BillingEmailTo__c', loaded.BillingEmailTo__c);
    values.put('BillingEmailCc__c', loaded.BillingEmailCc__c);
    values.put('BillingEmailBcc__c', loaded.BillingEmailBcc__c);
    for (String fieldApiName : BillingScheduleService.BILLING_ACCOUNT_SCHEDULE_FIELDS) {
      values.put(fieldApiName, loaded.get(fieldApiName));
    }
    return values;
  }

  private static String formatDate(Date value) {
    return InvoiceProductMergeService.formatDate(value);
  }

  private static InvoicePreviewDto buildInvoicePreviewFromCanonical(
    Id contractServiceId
  ) {
    InvoicePreviewDto preview = emptyPreview();
    if (contractServiceId == null) {
      return preview;
    }
    /** 仕様: Core 第11.9節、第1.1.10節 */
    GlAccountingSetting__mdt amountSetting = AmountCalculationSettingService.requireOrgDefault();
    preview.taxRoundingMode = amountSetting.TaxRoundingMode__c;
    preview.quantityUnitPriceRoundingMode = amountSetting.QuantityUnitPriceRoundingMode__c;
    preview.amountRoundingMode = amountSetting.AmountRoundingMode__c;
    preview.invoiceLockExemptFieldApiNames = tryLockExemptNames();
    preview.paymentLockExemptFieldApiNames = tryPaymentLockExemptNames();
    preview.journalLockExemptFieldApiNames = tryJournalLockExemptNames();

    List<Invoice__c> invoices = [
      SELECT
        Id,
        Name,
        MergeKey__c,
        InvoiceDate__c,
        PaymentScheduledDate__c,
        Amount__c,
        TaxAmount__c,
        TaxInclusiveAmount__c,
        TaxPercent__c,
        InvoiceTransactionStatus__c,
        DeliveryStatus__c,
        CollectionRefundStatus__c,
        DueStatus__c,
        OverdueDays__c,
        Memo__c,
        InvoicePaymentNet__c,
        SentDate__c,
        PaymentInclusiveTotal__c,
        SystemIntegrationDate__c,
        PaymentClearingCompletedDate__c,
        LastModifiedDate,
        IsManuallyAdjusted__c,
        IsAmountAdjusted__c,
        IsSplitMoved__c,
        PeriodLineAmountTotal__c,
        ContractHistory__r.Version__c,
        ContractService__r.Name,
        BillingAccountSnapShot__c,
        BillingAccountSnapShot__r.Name,
        BillingAddresseeSnapShot__c,
        BillingEmailToSnapShot__c,
        BillingEmailCcSnapShot__c,
        BillingEmailBccSnapShot__c,
        InvoiceDeliveryMethodSnapShot__c,
        PaymentTermMethodSnapShot__c,
        (
          SELECT
            Id,
            LineMergeKey__c,
            ProductName__c,
            HistoryVersionLabel__c,
            Unit__c,
            UnitPrice__c,
            Quantity__c,
            PeriodLabel__c,
            Amount__c,
            IsManuallyAdjusted__c,
            IsAmountAdjusted__c,
            IsSplitMoved__c,
            SourcePeriodLineIds__c,
            AcceptanceEndDate__c,
            RevenueRecognitionBasis__c,
            ContractProduct__c,
            ContractProduct__r.Amount__c,
            ContractProduct__r.Unit__c,
            ContractProduct__r.BillingType__c
          FROM InvoiceLines__r
          ORDER BY ProductName__c ASC NULLS LAST, CreatedDate ASC
        )
      FROM Invoice__c
      WHERE ContractService__c = :contractServiceId
      WITH SYSTEM_MODE
      ORDER BY InvoiceDate__c ASC NULLS LAST, CreatedDate ASC
    ];
    Set<Id> previewInvoiceIds = new Set<Id>();
    for (Invoice__c invoiceRecord : invoices) {
      previewInvoiceIds.add(invoiceRecord.Id);
    }
    Map<Id, Datetime> operationDatetimes = AccountingCauseLockService.resolveInvoiceOperationDatetimes(
      previewInvoiceIds
    );
    Map<Id, Map<String, Object>> invoiceExtraById =
      InvoiceOpsFieldService.readValuesById('Invoice__c', previewInvoiceIds);

    // 見積バーは Ordered CP.Amount を請求月数で按分した値（InvoiceProduct 金額合算ではない）。
    Decimal periodTotal = buildScopedEstimateSummary(contractServiceId).total;
    Decimal invoiceTotal = 0;
    Boolean hasManual = false;

    for (Invoice__c invoiceRecord : invoices) {
      InvoiceGroupDto invoice = new InvoiceGroupDto();
      invoice.invoiceId = invoiceRecord.Id;
      invoice.invoiceName = invoiceRecord.Name;
      invoice.mergeKey = invoiceRecord.MergeKey__c;
      invoice.contractServiceName = invoiceRecord.ContractService__r == null
        ? null
        : invoiceRecord.ContractService__r.Name;
      invoice.billingAccountId = invoiceRecord.BillingAccountSnapShot__c;
      invoice.billingAccountName = invoiceRecord.BillingAccountSnapShot__r ==
        null
        ? null
        : invoiceRecord.BillingAccountSnapShot__r.Name;
      invoice.billingAddressee = invoiceRecord.BillingAddresseeSnapShot__c;
      invoice.billingEmailTo = invoiceRecord.BillingEmailToSnapShot__c;
      invoice.billingEmailCc = invoiceRecord.BillingEmailCcSnapShot__c;
      invoice.billingEmailBcc = invoiceRecord.BillingEmailBccSnapShot__c;
      invoice.invoiceDeliveryMethod = invoiceRecord.InvoiceDeliveryMethodSnapShot__c;
      invoice.paymentTerm = invoiceRecord.PaymentTermMethodSnapShot__c;
      invoice.invoiceDate = formatDate(invoiceRecord.InvoiceDate__c);
      invoice.paymentScheduledDate = formatDate(
        invoiceRecord.PaymentScheduledDate__c
      );
      Decimal amountTotal = invoiceRecord.Amount__c == null
        ? 0
        : invoiceRecord.Amount__c;
      Decimal taxTotal = invoiceRecord.TaxAmount__c == null
        ? 0
        : invoiceRecord.TaxAmount__c;
      Decimal taxPercent = TaxCalculationUtil.fromPercentFieldStorage(
        invoiceRecord.TaxPercent__c
      );
      invoice.amountTotal = amountTotal;
      invoice.taxTotal = taxTotal;
      invoice.taxPercent = taxPercent;
      invoice.isManuallyAdjusted = invoiceRecord.IsManuallyAdjusted__c == true;
      invoice.isAmountAdjusted = invoiceRecord.IsAmountAdjusted__c == true;
      invoice.isSplitMoved = invoiceRecord.IsSplitMoved__c == true;
      invoice.historyVersion = invoiceRecord.ContractHistory__r == null
        ? null
        : invoiceRecord.ContractHistory__r.Version__c;
      Boolean locked = InvoiceLockUtil.isLocked(invoiceRecord);
      invoice.locked = locked;
      invoice.invoiceTransactionStatus = invoiceRecord.InvoiceTransactionStatus__c;
      invoice.deliveryStatus = invoiceRecord.DeliveryStatus__c;
      invoice.dueStatus = invoiceRecord.DueStatus__c;
      invoice.overdueDays = invoiceRecord.OverdueDays__c;
      invoice.accountingStatus = null;
      invoice.accountingIssueName = null;
      invoice.sentDate = invoiceRecord.SentDate__c;
      invoice.latestIssuedContentDocumentId = EstimateDocumentService.latestIssuedContentDocumentId(
        invoiceRecord.Id
      );
      invoice.memo = invoiceRecord.Memo__c;
      invoice.extraFieldValues = invoiceExtraById.get(invoiceRecord.Id);
      invoice.invoiceTransactionStatus = invoiceRecord.InvoiceTransactionStatus__c;
      invoice.isCancelled = InvoiceTransactionStatusService.isCancelled(
        invoiceRecord
      );
      invoice.invoicePaymentNet = invoiceRecord.InvoicePaymentNet__c == null
        ? 0
        : invoiceRecord.InvoicePaymentNet__c;
      invoice.taxInclusiveAmount = invoiceRecord.TaxInclusiveAmount__c == null
        ? amountTotal + taxTotal
        : invoiceRecord.TaxInclusiveAmount__c;
      invoice.paymentNetTotal = invoiceRecord.PaymentInclusiveTotal__c == null
        ? 0
        : invoiceRecord.PaymentInclusiveTotal__c;
      invoice.canConfirm = InvoiceTransactionStatusService.isDraft(invoiceRecord);
      invoice.canUnconfirm = false;
      invoice.lastModifiedToken = ContractOptimisticLockUtil.toToken(
        operationDatetimes.containsKey(invoiceRecord.Id)
          ? operationDatetimes.get(invoiceRecord.Id)
          : invoiceRecord.LastModifiedDate
      );
      InvoicePaymentStatusUtil.StatusAmounts statusAmounts = InvoicePaymentStatusUtil.resolveStatusAmounts(
        invoiceRecord,
        amountTotal
      );
      invoice.integratedAmount = statusAmounts.integratedAmount;
      invoice.clearedAmount = statusAmounts.clearedAmount;
      invoice.openAmount = statusAmounts.openAmount;
      invoice.lines = new List<InvoiceMergedLineDto>();

      if (!invoice.isCancelled) {
        invoiceTotal += amountTotal;
        preview.invoiceCount++;
        preview.totalAmount += amountTotal;
        preview.totalTaxAmount += taxTotal;
        preview.integratedAmount += invoice.integratedAmount;
        preview.clearedAmount += invoice.clearedAmount;
        preview.openAmount += invoice.openAmount;
      }
      if (invoice.isManuallyAdjusted) {
        hasManual = true;
      }

      if (invoiceRecord.InvoiceLines__r != null) {
        for (InvoiceLine__c lineRecord : invoiceRecord.InvoiceLines__r) {
          InvoiceMergedLineDto line = new InvoiceMergedLineDto();
          line.lineId = lineRecord.Id;
          line.lineMergeKey = lineRecord.LineMergeKey__c;
          line.productName = lineRecord.ProductName__c;
          line.historyVersionLabel = lineRecord.HistoryVersionLabel__c;
          line.historyVersions = new List<Decimal>();
          if (invoice.historyVersion != null) {
            line.historyVersions.add(invoice.historyVersion);
          }
          line.unitPrice = lineRecord.UnitPrice__c;
          line.unit = String.isNotBlank(lineRecord.Unit__c)
            ? lineRecord.Unit__c
            : (lineRecord.ContractProduct__r == null
                ? null
                : lineRecord.ContractProduct__r.Unit__c);
          line.quantity = lineRecord.Quantity__c;
          line.periodLabel = lineRecord.PeriodLabel__c;
          Decimal lineAmount = lineRecord.Amount__c == null
            ? 0
            : lineRecord.Amount__c;
          line.amount = lineAmount;
          line.taxAmount = 0;
          InvoicePaymentStatusUtil.StatusAmounts lineStatus = InvoicePaymentStatusUtil.allocateLineStatusAmounts(
            lineAmount,
            amountTotal,
            statusAmounts
          );
          line.integratedAmount = lineStatus.integratedAmount;
          line.clearedAmount = lineStatus.clearedAmount;
          line.openAmount = lineStatus.openAmount;
          line.isManuallyAdjusted = lineRecord.IsManuallyAdjusted__c == true;
          line.isAmountAdjusted = lineRecord.IsAmountAdjusted__c == true;
          line.isSplitMoved = lineRecord.IsSplitMoved__c == true;
          line.acceptanceEndDate = lineRecord.AcceptanceEndDate__c;
          line.revenueRecognitionBasis = ContractMetadataService.normalizeRevenueRecognitionBasis(
            lineRecord.RevenueRecognitionBasis__c
          );
          line.contractProductId = lineRecord.ContractProduct__c;
          line.sourceInvoiceProductIds = parseIdList(
            lineRecord.SourcePeriodLineIds__c
          );
          String billingType = lineRecord.ContractProduct__r == null
            ? null
            : lineRecord.ContractProduct__r.BillingType__c;
          line.isRecurring = ContractMetadataService.isRecurringBillingType(
            billingType
          );
          line.cycleCountLabel = buildCycleCountLabel(
            billingType,
            line.sourceInvoiceProductIds
          );
          invoice.lines.add(line);
          preview.lineCount++;
        }
      }

      preview.invoices.add(invoice);
    }

    preview.periodLineAmountTotal = periodTotal;
    preview.invoiceAmountTotal = invoiceTotal;
    preview.amountDifference = invoiceTotal - periodTotal;
    preview.hasManualAdjustment = hasManual;
    return preview;
  }

  /**
   * 端数調整実績 = 由来付き請求明細の金額合計 − 由来 InvoiceProduct 金額合計。
   * 請求日／BA 金額分割で同一期間 ID が明細間に重複しても、期間 ID は重複排除する
   * （明細ごとに由来合計を引くと偽の大きなマイナスになる）。
   * Version 別も同じ定義。
   */
  private static void applyManualAdjustmentAmounts(InvoicePreviewDto preview) {
    if (preview == null) {
      return;
    }
    preview.manualAdjustmentAmount = 0;
    if (preview.versionOptions != null) {
      for (VersionOptionDto option : preview.versionOptions) {
        if (option != null) {
          option.manualAdjustmentAmount = 0;
        }
      }
    }
    if (preview.invoices == null || preview.invoices.isEmpty()) {
      return;
    }

    Set<Id> sourceIds = new Set<Id>();
    for (InvoiceGroupDto invoice : preview.invoices) {
      if (invoice == null || invoice.lines == null) {
        continue;
      }
      for (InvoiceMergedLineDto line : invoice.lines) {
        if (line == null || line.sourceInvoiceProductIds == null) {
          continue;
        }
        sourceIds.addAll(line.sourceInvoiceProductIds);
      }
    }

    Map<Id, Decimal> sourceAmountById = new Map<Id, Decimal>();
    if (!sourceIds.isEmpty()) {
      for (InvoiceProduct__c source : [
        SELECT Id, Amount__c
        FROM InvoiceProduct__c
        WHERE Id IN :sourceIds
        WITH SYSTEM_MODE
      ]) {
        sourceAmountById.put(
          source.Id,
          source.Amount__c == null ? 0 : source.Amount__c
        );
      }
    }

    Map<String, VersionOptionDto> optionByValue = new Map<String, VersionOptionDto>();
    if (preview.versionOptions != null) {
      for (VersionOptionDto option : preview.versionOptions) {
        if (option != null && String.isNotBlank(option.value)) {
          optionByValue.put(option.value, option);
        }
      }
    }

    Decimal totalLineAmount = 0;
    Set<Id> uniqueSourceIds = new Set<Id>();
    Map<String, Decimal> lineAmountByVersion = new Map<String, Decimal>();
    Map<String, Set<Id>> sourceIdsByVersion = new Map<String, Set<Id>>();

    for (InvoiceGroupDto invoice : preview.invoices) {
      if (invoice == null || invoice.lines == null) {
        continue;
      }
      String versionValue = invoice.historyVersion == null
        ? null
        : String.valueOf(invoice.historyVersion.intValue());
      for (InvoiceMergedLineDto line : invoice.lines) {
        if (line == null || line.sourceInvoiceProductIds == null) {
          continue;
        }
        Set<Id> lineSourceIds = new Set<Id>();
        for (Id sourceId : line.sourceInvoiceProductIds) {
          if (sourceAmountById.containsKey(sourceId)) {
            lineSourceIds.add(sourceId);
          }
        }
        if (lineSourceIds.isEmpty()) {
          continue;
        }
        Decimal lineAmount = line.amount == null ? 0 : line.amount;
        totalLineAmount += lineAmount;
        uniqueSourceIds.addAll(lineSourceIds);
        if (versionValue == null || !optionByValue.containsKey(versionValue)) {
          continue;
        }
        Decimal versionLineAmount = lineAmountByVersion.containsKey(
            versionValue
          )
          ? lineAmountByVersion.get(versionValue)
          : 0;
        lineAmountByVersion.put(versionValue, versionLineAmount + lineAmount);
        if (!sourceIdsByVersion.containsKey(versionValue)) {
          sourceIdsByVersion.put(versionValue, new Set<Id>());
        }
        sourceIdsByVersion.get(versionValue).addAll(lineSourceIds);
      }
    }

    preview.manualAdjustmentAmount =
      totalLineAmount - sumSourceAmounts(uniqueSourceIds, sourceAmountById);
    for (String versionValue : lineAmountByVersion.keySet()) {
      VersionOptionDto option = optionByValue.get(versionValue);
      if (option == null) {
        continue;
      }
      option.manualAdjustmentAmount =
        lineAmountByVersion.get(versionValue) -
        sumSourceAmounts(
          sourceIdsByVersion.get(versionValue),
          sourceAmountById
        );
    }
  }

  private static Decimal sumSourceAmounts(
    Set<Id> sourceIds,
    Map<Id, Decimal> sourceAmountById
  ) {
    Decimal total = 0;
    if (sourceIds == null || sourceIds.isEmpty() || sourceAmountById == null) {
      return total;
    }
    for (Id sourceId : sourceIds) {
      if (!sourceAmountById.containsKey(sourceId)) {
        continue;
      }
      total += sourceAmountById.get(sourceId);
    }
    return total;
  }

  /**
   * 明細ごとの端数ずれ = 請求明細金額 − 見積（CP.Amount を請求月数で按分）。
   * 上部バーの「見積額 vs 請求額」と同じ定義。
   * 継続: Amount × (ユニーク請求月数 / CP月数)。同一 CP 複数明細への配分は
   * 由来 InvoiceProduct 金額比（期間 ID 重複時はその期間金額を明細金額比で按分）。
   * 一回: 請求明細があれば Amount 全額を金額比で配分。
   */
  private static void applyEstimateDriftToLines(InvoicePreviewDto preview) {
    if (preview == null || preview.invoices == null) {
      return;
    }

    List<InvoiceMergedLineDto> allLines = new List<InvoiceMergedLineDto>();
    Set<Id> sourceIds = new Set<Id>();
    for (InvoiceGroupDto invoice : preview.invoices) {
      if (invoice == null || invoice.lines == null) {
        continue;
      }
      for (InvoiceMergedLineDto line : invoice.lines) {
        if (line == null) {
          continue;
        }
        line.sourceAmountTotal = null;
        line.amountDeltaFromSource = null;
        line.hasAmountDrift = false;
        allLines.add(line);
        if (line.sourceInvoiceProductIds != null) {
          sourceIds.addAll(line.sourceInvoiceProductIds);
        }
      }
    }
    if (allLines.isEmpty()) {
      return;
    }

    // InvoiceLine.ContractProduct が空でも、由来 InvoiceProduct から CP を復元する
    Map<Id, Id> contractProductBySourceId = new Map<Id, Id>();
    Map<Id, Decimal> periodAmountById = new Map<Id, Decimal>();
    if (!sourceIds.isEmpty()) {
      for (InvoiceProduct__c source : [
        SELECT Id, ContractProduct__c, Amount__c
        FROM InvoiceProduct__c
        WHERE Id IN :sourceIds
        WITH SYSTEM_MODE
      ]) {
        periodAmountById.put(
          source.Id,
          source.Amount__c == null ? 0 : source.Amount__c
        );
        if (source.ContractProduct__c != null) {
          contractProductBySourceId.put(source.Id, source.ContractProduct__c);
        }
      }
    }

    Set<Id> contractProductIds = new Set<Id>();
    Map<Id, Id> lineCpByLineId = new Map<Id, Id>();
    for (InvoiceMergedLineDto line : allLines) {
      Id cpId = line.contractProductId;
      if (cpId == null && line.sourceInvoiceProductIds != null) {
        for (Id sourceId : line.sourceInvoiceProductIds) {
          if (contractProductBySourceId.containsKey(sourceId)) {
            cpId = contractProductBySourceId.get(sourceId);
            break;
          }
        }
      }
      if (cpId == null || line.lineId == null) {
        continue;
      }
      line.contractProductId = cpId;
      lineCpByLineId.put(line.lineId, cpId);
      contractProductIds.add(cpId);
    }
    if (contractProductIds.isEmpty()) {
      return;
    }

    Map<Id, ContractProduct__c> productById = new Map<Id, ContractProduct__c>();
    for (ContractProduct__c product : [
      SELECT Id, Amount__c, BillingType__c, StartDate__c, Enddate__c
      FROM ContractProduct__c
      WHERE Id IN :contractProductIds
      WITH SYSTEM_MODE
    ]) {
      productById.put(product.Id, product);
    }

    Map<Id, Decimal> invoiceTotalByCp = new Map<Id, Decimal>();
    Map<Id, List<InvoiceMergedLineDto>> linesByCp = new Map<Id, List<InvoiceMergedLineDto>>();
    for (InvoiceMergedLineDto line : allLines) {
      Id cpId = line.lineId == null ? null : lineCpByLineId.get(line.lineId);
      if (cpId == null || !productById.containsKey(cpId)) {
        continue;
      }
      Decimal lineAmount = line.amount == null ? 0 : line.amount;
      Decimal current = invoiceTotalByCp.containsKey(cpId)
        ? invoiceTotalByCp.get(cpId)
        : 0;
      invoiceTotalByCp.put(cpId, current + lineAmount);
      if (!linesByCp.containsKey(cpId)) {
        linesByCp.put(cpId, new List<InvoiceMergedLineDto>());
      }
      linesByCp.get(cpId).add(line);
    }

    for (Id cpId : linesByCp.keySet()) {
      List<InvoiceMergedLineDto> cpLines = linesByCp.get(cpId);
      ContractProduct__c product = productById.get(cpId);
      if (cpLines == null || cpLines.isEmpty() || product == null) {
        continue;
      }
      Decimal estimate = product.Amount__c == null ? 0 : product.Amount__c;
      Boolean recurring = ContractMetadataService.isRecurringBillingType(
        product.BillingType__c
      );
      if (recurring) {
        applyRecurringEstimateDriftToCpLines(
          cpLines,
          product,
          estimate,
          periodAmountById
        );
      } else {
        applyOneTimeEstimateDriftToCpLines(
          cpLines,
          estimate,
          invoiceTotalByCp.containsKey(cpId) ? invoiceTotalByCp.get(cpId) : 0
        );
      }
    }
  }

  /**
   * 継続課金の見積按分を明細へ配分する。
   * scopedEstimate は従来どおり月数按分。
   * - 期間 ID が明細間で重複（金額／単価／数量分割のコピー）→ 明細金額比。
   *   片方だけ期間パーティションした混在状態で IP 金額比を使うと行だけ数千円の偽ずれになる。
   * - 期間 ID が排他的（しきい日分割後など）→ 由来 InvoiceProduct 金額比。
   */
  private static void applyRecurringEstimateDriftToCpLines(
    List<InvoiceMergedLineDto> cpLines,
    ContractProduct__c product,
    Decimal estimate,
    Map<Id, Decimal> periodAmountById
  ) {
    Set<Id> uniquePeriodIds = new Set<Id>();
    Map<Id, List<InvoiceMergedLineDto>> linesByPeriodId = new Map<Id, List<InvoiceMergedLineDto>>();
    Map<Id, Decimal> weightByLineId = new Map<Id, Decimal>();

    for (InvoiceMergedLineDto line : cpLines) {
      if (line == null || line.lineId == null) {
        continue;
      }
      weightByLineId.put(line.lineId, 0);
      if (line.sourceInvoiceProductIds == null) {
        continue;
      }
      Set<Id> seenOnLine = new Set<Id>();
      for (Id periodId : line.sourceInvoiceProductIds) {
        if (
          periodId == null ||
          seenOnLine.contains(periodId) ||
          periodAmountById == null ||
          !periodAmountById.containsKey(periodId)
        ) {
          continue;
        }
        seenOnLine.add(periodId);
        uniquePeriodIds.add(periodId);
        if (!linesByPeriodId.containsKey(periodId)) {
          linesByPeriodId.put(periodId, new List<InvoiceMergedLineDto>());
        }
        linesByPeriodId.get(periodId).add(line);
      }
    }

    Integer totalMonths = uniquePeriodIds.size();
    Decimal scopedEstimate = scopeEstimateAmount(product, estimate, totalMonths);
    if (totalMonths < 1) {
      for (InvoiceMergedLineDto line : cpLines) {
        Decimal lineAmount = line.amount == null ? 0 : line.amount;
        line.sourceAmountTotal = 0;
        line.amountDeltaFromSource = lineAmount;
        line.hasAmountDrift = lineAmount != 0;
      }
      return;
    }

    Boolean hasSharedPeriod = false;
    for (Id periodId : uniquePeriodIds) {
      List<InvoiceMergedLineDto> owners = linesByPeriodId.get(periodId);
      if (owners != null && owners.size() > 1) {
        hasSharedPeriod = true;
        break;
      }
    }
    if (hasSharedPeriod) {
      Decimal invoiceTotal = 0;
      for (InvoiceMergedLineDto line : cpLines) {
        invoiceTotal += line.amount == null ? 0 : line.amount;
      }
      applyOneTimeEstimateDriftToCpLines(cpLines, scopedEstimate, invoiceTotal);
      return;
    }

    Boolean anyNonZeroPeriodAmount = false;
    for (Id periodId : uniquePeriodIds) {
      Decimal periodAmount = periodAmountById.get(periodId);
      if (periodAmount != null && periodAmount != 0) {
        anyNonZeroPeriodAmount = true;
        break;
      }
    }

    for (Id periodId : uniquePeriodIds) {
      Decimal periodWeight = anyNonZeroPeriodAmount
        ? periodAmountById.get(periodId)
        : 1;
      if (periodWeight == null) {
        periodWeight = 0;
      }
      List<InvoiceMergedLineDto> owners = linesByPeriodId.get(periodId);
      if (owners == null || owners.isEmpty()) {
        continue;
      }
      Id ownerLineId = owners[0].lineId;
      weightByLineId.put(
        ownerLineId,
        weightByLineId.get(ownerLineId) + periodWeight
      );
    }

    Decimal totalWeight = 0;
    for (InvoiceMergedLineDto line : cpLines) {
      if (line == null || line.lineId == null) {
        continue;
      }
      totalWeight += weightByLineId.containsKey(line.lineId)
        ? weightByLineId.get(line.lineId)
        : 0;
    }
    if (totalWeight == 0) {
      Decimal invoiceTotal = 0;
      for (InvoiceMergedLineDto line : cpLines) {
        invoiceTotal += line.amount == null ? 0 : line.amount;
      }
      applyOneTimeEstimateDriftToCpLines(cpLines, scopedEstimate, invoiceTotal);
      return;
    }

    Decimal remainingEstimate = scopedEstimate;
    for (Integer i = 0; i < cpLines.size(); i++) {
      InvoiceMergedLineDto line = cpLines[i];
      Decimal lineAmount = line.amount == null ? 0 : line.amount;
      Decimal lineWeight = weightByLineId.containsKey(line.lineId)
        ? weightByLineId.get(line.lineId)
        : 0;
      Decimal lineEstimate;
      if (i == cpLines.size() - 1) {
        lineEstimate = remainingEstimate;
      } else {
        lineEstimate = (scopedEstimate *
          lineWeight /
          totalWeight)
          .setScale(0, System.RoundingMode.HALF_UP);
        remainingEstimate -= lineEstimate;
      }
      line.sourceAmountTotal = lineEstimate;
      line.amountDeltaFromSource = lineAmount - lineEstimate;
      line.hasAmountDrift = line.amountDeltaFromSource != 0;
    }
  }

  private static void applyOneTimeEstimateDriftToCpLines(
    List<InvoiceMergedLineDto> cpLines,
    Decimal estimate,
    Decimal invoiceTotal
  ) {
    // 一回課金: 請求に載っていれば Amount 全額を比較元にし、明細間は金額比で配分。
    Decimal scopedEstimate = estimate == null ? 0 : estimate;
    if (invoiceTotal == 0) {
      Decimal remainingEstimate = scopedEstimate;
      for (Integer i = 0; i < cpLines.size(); i++) {
        InvoiceMergedLineDto line = cpLines[i];
        Decimal lineAmount = line.amount == null ? 0 : line.amount;
        Decimal lineEstimate = 0;
        if (i == cpLines.size() - 1) {
          lineEstimate = remainingEstimate;
        }
        line.sourceAmountTotal = lineEstimate;
        line.amountDeltaFromSource = lineAmount - lineEstimate;
        line.hasAmountDrift = line.amountDeltaFromSource != 0;
      }
      return;
    }

    Decimal remainingEstimate = scopedEstimate;
    for (Integer i = 0; i < cpLines.size(); i++) {
      InvoiceMergedLineDto line = cpLines[i];
      Decimal lineAmount = line.amount == null ? 0 : line.amount;
      Decimal lineEstimate;
      if (i == cpLines.size() - 1) {
        lineEstimate = remainingEstimate;
      } else {
        lineEstimate = (scopedEstimate *
          lineAmount /
          invoiceTotal)
          .setScale(0, System.RoundingMode.HALF_UP);
        remainingEstimate -= lineEstimate;
      }
      line.sourceAmountTotal = lineEstimate;
      line.amountDeltaFromSource = lineAmount - lineEstimate;
      line.hasAmountDrift = line.amountDeltaFromSource != 0;
    }
  }

  private class ScopedEstimateSummary {
    public Decimal total = 0;
    public Map<String, Decimal> byVersion = new Map<String, Decimal>();
  }

  /**
   * 仕様: Core 第7.8.5節、第7.9.1節。
   * 見積税抜は Ordered 契約履歴の DeltaAmountSum__c。件数按分は使わない。
   */
  private static ScopedEstimateSummary buildScopedEstimateSummary(
    Id contractServiceId
  ) {
    ScopedEstimateSummary summary = new ScopedEstimateSummary();
    if (contractServiceId == null) {
      return summary;
    }

    Set<Decimal> seenVersions = new Set<Decimal>();
    for (ContractHistory__c history : [
      SELECT Version__c, DeltaAmountSum__c
      FROM ContractHistory__c
      WHERE
        ContractService__c = :contractServiceId
        AND historystatus__c = :HISTORY_STATUS_ORDERED
      WITH SYSTEM_MODE
      ORDER BY Version__c ASC
    ]) {
      if (history.Version__c == null || seenVersions.contains(history.Version__c)) {
        continue;
      }
      seenVersions.add(history.Version__c);
      Decimal amount = history.DeltaAmountSum__c == null
        ? 0
        : history.DeltaAmountSum__c;
      summary.total += amount;
      String value = String.valueOf(history.Version__c.intValue());
      summary.byVersion.put(value, amount);
    }
    return summary;
  }

  /** 仕様: Core 第7.8.5節。明細側の参照用。見積税抜合計の正本は buildScopedEstimateSummary。 */
  private static Decimal scopeEstimateAmount(
    ContractProduct__c product,
    Decimal amount,
    Integer invoicedMonths
  ) {
    if (amount == null || invoicedMonths == null || invoicedMonths < 1) {
      return 0;
    }
    if (
      product == null ||
      !ContractMetadataService.isRecurringBillingType(product.BillingType__c)
    ) {
      return amount;
    }
    Integer cycles = resolveCpCycles(product);
    if (cycles < 1) {
      return amount;
    }
    return (amount * invoicedMonths / cycles)
      .setScale(0, RoundingMode.HALF_UP);
  }

  private static Decimal loadServiceDisplayTaxPercent(Id contractServiceId) {
    if (contractServiceId == null) {
      return null;
    }
    List<ContractService__c> services = [
      SELECT TaxPercent__c
      FROM ContractService__c
      WHERE Id = :contractServiceId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (services.isEmpty()) {
      return null;
    }
    return TaxCalculationUtil.fromPercentFieldStorage(
      services[0].TaxPercent__c
    );
  }

  private static Decimal inclusiveFromExcl(
    Decimal excl,
    Decimal displayPercent
  ) {
    Decimal amount = excl == null ? 0 : excl;
    if (displayPercent == null) {
      return amount;
    }
    try {
      return TaxCalculationUtil.calculateAmountInclTax(amount, displayPercent);
    } catch (TaxCalculationUtil.TaxPercentException ex) {
      return amount;
    }
  }

  private static Integer resolveCpCycles(ContractProduct__c product) {
    if (
      product == null ||
      !ContractMetadataService.isRecurringBillingType(product.BillingType__c)
    ) {
      return 1;
    }
    if (product.StartDate__c == null || product.Enddate__c == null) {
      return 1;
    }
    Integer cycles = MonthlyBillingPeriodUtil.countMonthlyCycles(
      product.StartDate__c,
      product.Enddate__c
    );
    return cycles == null || cycles < 1 ? 1 : cycles;
  }

  private static Integer countLineMonths(
    InvoiceMergedLineDto line,
    Boolean recurring
  ) {
    if (!recurring) {
      return 1;
    }
    if (line == null || line.sourceInvoiceProductIds == null) {
      return 0;
    }
    return line.sourceInvoiceProductIds.size();
  }

  private static String buildCycleCountLabel(
    String billingType,
    List<Id> sourcePeriodLineIds
  ) {
    if (!ContractMetadataService.isRecurringBillingType(billingType)) {
      return '-';
    }
    Integer count = sourcePeriodLineIds == null
      ? 0
      : sourcePeriodLineIds.size();
    if (count < 1) {
      return '-';
    }
    return String.valueOf(count) + ' month';
  }

  private static List<Id> parseIdList(String raw) {
    List<Id> ids = new List<Id>();
    if (String.isBlank(raw)) {
      return ids;
    }
    for (String part : raw.split(',')) {
      String trimmed = part == null ? null : part.trim();
      if (String.isBlank(trimmed)) {
        continue;
      }
      try {
        ids.add((Id) trimmed);
      } catch (Exception ignore) {
        // 監査用文字列のため不正値は無視
      }
    }
    return ids;
  }

  private static List<String> tryLockExemptNames() {
    try {
      return new List<String>(InvoiceLockUtil.resolveLockExemptFieldNames());
    } catch (InvoiceLockUtil.LockExemptException ex) {
      return new List<String>();
    }
  }

  private static List<String> tryPaymentLockExemptNames() {
    try {
      return new List<String>(
        InvoicePaymentLockUtil.resolveLockExemptFieldNames()
      );
    } catch (InvoicePaymentLockUtil.LockExemptException ex) {
      return new List<String>();
    }
  }

  private static List<String> tryJournalLockExemptNames() {
    try {
      return new List<String>(JournalLockService.resolveLockExemptFieldNames());
    } catch (JournalLockService.LockException ex) {
      return new List<String>();
    }
  }

  private static InvoicePreviewDto emptyPreview() {
    InvoicePreviewDto preview = new InvoicePreviewDto();
    preview.totalAmount = 0;
    preview.totalTaxAmount = 0;
    preview.integratedAmount = 0;
    preview.clearedAmount = 0;
    preview.openAmount = 0;
    preview.invoiceCount = 0;
    preview.lineCount = 0;
    preview.invoices = new List<InvoiceGroupDto>();
    preview.versionOptions = new List<VersionOptionDto>();
    preview.canView = false;
    preview.canEdit = false;
    preview.versionEditBlocked = false;
    preview.periodLineAmountTotal = 0;
    preview.periodLineTaxInclusiveTotal = 0;
    preview.invoiceAmountTotal = 0;
    preview.invoiceTaxInclusiveTotal = 0;
    preview.amountDifference = 0;
    preview.manualAdjustmentAmount = 0;
    preview.hasManualAdjustment = false;
    preview.operationDay = InvoiceTransactionStatusService.organizationToday();
    return preview;
  }

  private static Map<String, Object> parseCustomFields(String jsonText) {
    if (String.isBlank(jsonText)) {
      return new Map<String, Object>();
    }
    Object parsed = JSON.deserializeUntyped(jsonText);
    if (!(parsed instanceof Map<String, Object>)) {
      return new Map<String, Object>();
    }
    return (Map<String, Object>) parsed;
  }
}
