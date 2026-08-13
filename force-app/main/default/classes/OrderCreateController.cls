/**
 * 受注ウィザード（orderCreate*）向け Apex コントローラ。
 * 見積→受注、取消、請求ロック確認などのサーバ処理を提供する。
 */
public without sharing class OrderCreateController {
  private static final String HISTORY_STATUS_ESTIMATE = ContractDomainConstants.HISTORY_STATUS_ESTIMATE;
  private static final String HISTORY_STATUS_ORDERED = ContractDomainConstants.HISTORY_STATUS_ORDERED;
  private static final String HISTORY_TYPE_CANCEL = ContractDomainConstants.HISTORY_TYPE_CANCEL;
  private static final String HISTORY_TYPE_ADD = ContractDomainConstants.HISTORY_TYPE_ADD;
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

    /** 差し戻し画面で「更新商談を削除」を出すか（作成済みがある） */
    @AuraEnabled
    public Boolean hasRenewOpportunity;

    @AuraEnabled
    public Id renewOpportunityId;

    /** 同時編集ガード用。ContractHistory.LastModifiedDate の epoch ms */
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
    public Decimal invoiceAmountTotal;

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
    public Decimal invoiceAmountTotal;

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
  }

  @AuraEnabled
  public static OrderContextDto getOrderContext(Id contractHistoryId) {
    if (contractHistoryId == null) {
      throw toAuraHandled('契約履歴IDが指定されていません。');
    }

    List<ContractHistory__c> histories = queryContractHistoryForOrderContext(
      contractHistoryId
    );
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
      !shouldSkipRenewOpportunity(history);
    dto.renewOpportunityId = RenewOpportunityCreateService.findBySourceHistory(
      history.Id
    );
    dto.hasRenewOpportunity = dto.renewOpportunityId != null;
    dto.lastModifiedToken = ContractOptimisticLockUtil.toToken(
      history.LastModifiedDate
    );
    dto.products = loadProductLines(history.Id);
    dto.billingSettings = buildBillingSettings(
      history.ContractService__r.BiilingAcccount__r
    );
    dto.historyCustomFields = OrderWizardFieldService.buildHistoryCustomFieldValues(
      history
    );
    dto.billingCustomFields = buildBillingCustomFields(
      history.ContractService__r.BiilingAcccount__r
    );
    return dto;
  }

  @AuraEnabled
  public static OrderSaveResult saveOrderStep1(
    Id contractHistoryId,
    String historyCustomFieldsJson
  ) {
    assertOrderPermission();
    ContractHistory__c history = loadEstimateHistory(contractHistoryId);
    OrderWizardFieldService.applyHistoryFields(
      history,
      parseCustomFields(historyCustomFieldsJson)
    );
    SystemContextAccess.updateRecords(new List<ContractHistory__c>{ history });

    OrderSaveResult result = new OrderSaveResult();
    result.contractHistoryId = history.Id;
    result.historyStatus = history.historystatus__c;
    return result;
  }

  @AuraEnabled
  public static OrderSaveResult saveOrderStep2(
    Id contractHistoryId,
    String billingCustomFieldsJson
  ) {
    throw toAuraHandled(
      '受注ウィザードからの請求アカウント更新は廃止しました。取引先の関連リストで請求アカウントを編集してください。'
    );
  }

  /** deleteRenewOpportunity は呼び出し側で明示すること（省略 overload は持たない） */
  public static OrderSaveResult revertOrder(
    Id contractHistoryId,
    Boolean deleteRenewOpportunity
  ) {
    return revertOrder(contractHistoryId, deleteRenewOpportunity, null);
  }

  @AuraEnabled
  public static OrderSaveResult revertOrder(
    Id contractHistoryId,
    Boolean deleteRenewOpportunity,
    String expectedLastModifiedToken
  ) {
    assertRevertPermission();
    ContractHistory__c history = loadOrderedHistory(contractHistoryId);
    ContractOptimisticLockUtil.assertHistoryUnchanged(
      history,
      expectedLastModifiedToken
    );
    String blockedReason = buildRevertBlockedReason(
      history.Id,
      history.historystatus__c
    );
    if (String.isNotBlank(blockedReason)) {
      throw toAuraHandled(blockedReason);
    }

    history.historystatus__c = HISTORY_STATUS_ESTIMATE;
    try {
      SystemContextAccess.updateRecords(
        new List<ContractHistory__c>{ history }
      );
      if (deleteRenewOpportunity == true) {
        RenewOpportunityCreateService.deleteBySourceHistory(history.Id);
      }
    } catch (RenewOpportunityCreateService.RenewOpportunityException ex) {
      throw toAuraHandled(ex.getMessage());
    } catch (DmlException ex) {
      throw toAuraHandled(extractDmlMessage(ex));
    } catch (Exception ex) {
      throw toAuraHandled(
        String.isNotBlank(ex.getMessage())
          ? ex.getMessage()
          : '差し戻し処理中にエラーが発生しました。'
      );
    }

    OrderSaveResult result = new OrderSaveResult();
    result.contractHistoryId = history.Id;
    result.historyStatus = HISTORY_STATUS_ESTIMATE;
    return result;
  }

  /** createRenewOpportunity は呼び出し側で明示すること（省略 overload は持たない） */
  public static OrderSaveResult confirmOrder(
    Id contractHistoryId,
    String billingCustomFieldsJson,
    Boolean createRenewOpportunity
  ) {
    return confirmOrder(
      contractHistoryId,
      billingCustomFieldsJson,
      createRenewOpportunity,
      null
    );
  }

  @AuraEnabled
  public static OrderSaveResult confirmOrder(
    Id contractHistoryId,
    String billingCustomFieldsJson,
    Boolean createRenewOpportunity,
    String expectedLastModifiedToken
  ) {
    assertOrderPermission();
    ContractHistory__c history = loadEstimateHistory(contractHistoryId);
    ContractOptimisticLockUtil.assertHistoryUnchanged(
      history,
      expectedLastModifiedToken
    );
    validateReadyForOrder(history);

    history.historystatus__c = HISTORY_STATUS_ORDERED;
    Id renewOpportunityId = null;
    try {
      SystemContextAccess.updateRecords(
        new List<ContractHistory__c>{ history }
      );
      if (
        createRenewOpportunity == true &&
        !shouldSkipRenewOpportunity(history)
      ) {
        renewOpportunityId = RenewOpportunityCreateService.createFromOrderedHistory(
          history.Id
        );
      }
    } catch (RenewOpportunityCreateService.RenewOpportunityException ex) {
      throw toAuraHandled(ex.getMessage());
    } catch (DmlException ex) {
      throw toAuraHandled(extractConfirmOrderDmlMessage(ex));
    } catch (InvoiceLockUtil.InvoiceLockException ex) {
      throw toAuraHandled(ex.getMessage());
    } catch (InvoiceProductFieldCopyService.FieldCopyException ex) {
      throw toAuraHandled(ex.getMessage());
    } catch (Exception ex) {
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

  @AuraEnabled
  public static InvoicePreviewDto getInvoicePreview(Id contractHistoryId) {
    ContractPermissionUtil.assertViewInvoicePreview();
    if (contractHistoryId == null) {
      return emptyPreview();
    }

    ContractHistory__c sourceHistory = resolveHistoryForPreview(contractHistoryId);
    if (sourceHistory == null || sourceHistory.ContractService__c == null) {
      return emptyPreview();
    }
    Id contractServiceId = sourceHistory.ContractService__c;

    // 既存受注分で請求正本が無い場合は契約期間明細からバックフィル
    InvoiceCanonicalService.backfillMissingForContractService(contractServiceId);

    InvoicePreviewDto preview = buildInvoicePreviewFromCanonical(
      contractServiceId
    );
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
    return preview;
  }

  public static InvoicePreviewDto updateInvoiceLineAmount(
    Id contractHistoryId,
    Id lineId,
    Decimal amount
  ) {
    return updateInvoiceLineAmount(
      contractHistoryId,
      lineId,
      amount,
      null
    );
  }

  @AuraEnabled
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
      expectedContentVersion
    );
  }

  public static InvoicePreviewDto updateInvoiceLineAmounts(
    Id contractHistoryId,
    List<InvoiceCanonicalService.LineAmountEdit> edits
  ) {
    return updateInvoiceLineAmounts(contractHistoryId, edits, null);
  }

  @AuraEnabled
  public static InvoicePreviewDto updateInvoiceLineAmounts(
    Id contractHistoryId,
    List<InvoiceCanonicalService.LineAmountEdit> edits,
    String expectedContentVersion
  ) {
    assertPreviewContentUnchanged(contractHistoryId, expectedContentVersion);
    try {
      InvoiceCanonicalService.updateLineAmounts(edits);
    } catch (Exception ex) {
      throw toAuraHandled(ex.getMessage());
    }
    return getInvoicePreview(contractHistoryId);
  }

  public static InvoicePreviewDto updateInvoiceDates(
    Id contractHistoryId,
    Id invoiceId,
    Date invoiceDate,
    Date paymentScheduledDate
  ) {
    return updateInvoiceDates(
      contractHistoryId,
      invoiceId,
      invoiceDate,
      paymentScheduledDate,
      null
    );
  }

  @AuraEnabled
  public static InvoicePreviewDto updateInvoiceDates(
    Id contractHistoryId,
    Id invoiceId,
    Date invoiceDate,
    Date paymentScheduledDate,
    String expectedContentVersion
  ) {
    assertPreviewContentUnchanged(contractHistoryId, expectedContentVersion);
    try {
      InvoiceCanonicalService.updateInvoiceDates(
        invoiceId,
        invoiceDate,
        paymentScheduledDate
      );
    } catch (Exception ex) {
      throw toAuraHandled(ex.getMessage());
    }
    return getInvoicePreview(contractHistoryId);
  }

  public static InvoicePreviewDto updateInvoiceBillingHeader(
    Id contractHistoryId,
    Id invoiceId,
    Id billingAccountId,
    String billingAddressee,
    String billingEmailTo,
    String billingEmailCc,
    String billingEmailBcc,
    String paymentTerm,
    Decimal taxPercent
  ) {
    return updateInvoiceBillingHeader(
      contractHistoryId,
      invoiceId,
      billingAccountId,
      billingAddressee,
      billingEmailTo,
      billingEmailCc,
      billingEmailBcc,
      paymentTerm,
      taxPercent,
      null
    );
  }

  @AuraEnabled
  public static InvoicePreviewDto updateInvoiceBillingHeader(
    Id contractHistoryId,
    Id invoiceId,
    Id billingAccountId,
    String billingAddressee,
    String billingEmailTo,
    String billingEmailCc,
    String billingEmailBcc,
    String paymentTerm,
    Decimal taxPercent,
    String expectedContentVersion
  ) {
    assertPreviewContentUnchanged(contractHistoryId, expectedContentVersion);
    try {
      // billingAccountId / paymentTerm はサービス側で無視（SnapShot 宛名・メール・税率を更新）
      InvoiceCanonicalService.updateInvoiceBillingHeader(
        invoiceId,
        billingAccountId,
        billingAddressee,
        billingEmailTo,
        billingEmailCc,
        billingEmailBcc,
        paymentTerm,
        taxPercent
      );
    } catch (Exception ex) {
      throw toAuraHandled(ex.getMessage());
    }
    return getInvoicePreview(contractHistoryId);
  }

  /**
   * 請求プレビュー「請求情報編集」一体保存（日付＋宛名／メール／税率を 1 DML）。
   */
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
    String expectedContentVersion
  ) {
    assertPreviewContentUnchanged(contractHistoryId, expectedContentVersion);
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
        taxPercent
      );
    } catch (Exception ex) {
      throw toAuraHandled(ex.getMessage());
    }
    return getInvoicePreview(contractHistoryId);
  }

  public static InvoicePreviewDto splitInvoiceByDate(
    Id contractHistoryId,
    Id sourceInvoiceId,
    Date newInvoiceDate,
    Date newPaymentScheduledDate,
    List<InvoiceCanonicalService.SplitLineInput> splitLines
  ) {
    return splitInvoiceByDate(
      contractHistoryId,
      sourceInvoiceId,
      newInvoiceDate,
      newPaymentScheduledDate,
      splitLines,
      null
    );
  }

  @AuraEnabled
  public static InvoicePreviewDto splitInvoiceByDate(
    Id contractHistoryId,
    Id sourceInvoiceId,
    Date newInvoiceDate,
    Date newPaymentScheduledDate,
    List<InvoiceCanonicalService.SplitLineInput> splitLines,
    String expectedContentVersion
  ) {
    assertPreviewContentUnchanged(contractHistoryId, expectedContentVersion);
    try {
      InvoiceCanonicalService.splitInvoiceByDate(
        sourceInvoiceId,
        newInvoiceDate,
        newPaymentScheduledDate,
        splitLines
      );
    } catch (Exception ex) {
      throw toAuraHandled(ex.getMessage());
    }
    return getInvoicePreview(contractHistoryId);
  }

  public static InvoicePreviewDto splitInvoiceByBillingAccount(
    Id contractHistoryId,
    Id sourceInvoiceId,
    Id newBillingAccountId,
    Date newInvoiceDate,
    Date newPaymentScheduledDate,
    List<InvoiceCanonicalService.SplitLineInput> splitLines
  ) {
    return splitInvoiceByBillingAccount(
      contractHistoryId,
      sourceInvoiceId,
      newBillingAccountId,
      newInvoiceDate,
      newPaymentScheduledDate,
      splitLines,
      null
    );
  }

  @AuraEnabled
  public static InvoicePreviewDto splitInvoiceByBillingAccount(
    Id contractHistoryId,
    Id sourceInvoiceId,
    Id newBillingAccountId,
    Date newInvoiceDate,
    Date newPaymentScheduledDate,
    List<InvoiceCanonicalService.SplitLineInput> splitLines,
    String expectedContentVersion
  ) {
    assertPreviewContentUnchanged(contractHistoryId, expectedContentVersion);
    try {
      InvoiceCanonicalService.splitInvoiceByBillingAccount(
        sourceInvoiceId,
        newBillingAccountId,
        newInvoiceDate,
        newPaymentScheduledDate,
        splitLines
      );
    } catch (Exception ex) {
      throw toAuraHandled(ex.getMessage());
    }
    return getInvoicePreview(contractHistoryId);
  }

  public static InvoicePreviewDto splitInvoiceByPeriod(
    Id contractHistoryId,
    Id sourceInvoiceId,
    Date newInvoiceDate,
    Date newPaymentScheduledDate,
    List<Id> movePeriodLineIds,
    Id newBillingAccountId
  ) {
    return splitInvoiceByPeriod(
      contractHistoryId,
      sourceInvoiceId,
      newInvoiceDate,
      newPaymentScheduledDate,
      movePeriodLineIds,
      newBillingAccountId,
      null
    );
  }

  @AuraEnabled
  public static InvoicePreviewDto splitInvoiceByPeriod(
    Id contractHistoryId,
    Id sourceInvoiceId,
    Date newInvoiceDate,
    Date newPaymentScheduledDate,
    List<Id> movePeriodLineIds,
    Id newBillingAccountId,
    String expectedContentVersion
  ) {
    assertPreviewContentUnchanged(contractHistoryId, expectedContentVersion);
    try {
      InvoiceCanonicalService.splitInvoiceByPeriod(
        sourceInvoiceId,
        newInvoiceDate,
        newPaymentScheduledDate,
        movePeriodLineIds,
        newBillingAccountId
      );
    } catch (Exception ex) {
      throw toAuraHandled(ex.getMessage());
    }
    return getInvoicePreview(contractHistoryId);
  }

  /**
   * 選択明細を既存請求へ全額移す（請求プレビュー「明細を移す」）。
   */
  @AuraEnabled
  public static InvoicePreviewDto moveLinesToExistingInvoice(
    Id contractHistoryId,
    Id sourceInvoiceId,
    Id targetInvoiceId,
    List<Id> lineIds,
    String expectedContentVersion
  ) {
    assertPreviewContentUnchanged(contractHistoryId, expectedContentVersion);
    try {
      InvoiceCanonicalService.moveLinesToExistingInvoice(
        sourceInvoiceId,
        targetInvoiceId,
        lineIds
      );
    } catch (Exception ex) {
      throw toAuraHandled(ex.getMessage());
    }
    return getInvoicePreview(contractHistoryId);
  }

  /**
   * 統一分割（明細ごと／単価／個数／月の混在）。請求プレビュー「わける」から呼ぶ。
   */
  @AuraEnabled
  public static InvoicePreviewDto splitInvoiceUnified(
    Id contractHistoryId,
    Id sourceInvoiceId,
    Date newInvoiceDate,
    Date newPaymentScheduledDate,
    Id newBillingAccountId,
    List<InvoiceCanonicalService.SplitLineInput> splitLines,
    String expectedContentVersion
  ) {
    assertPreviewContentUnchanged(contractHistoryId, expectedContentVersion);
    try {
      InvoiceCanonicalService.splitInvoiceUnified(
        sourceInvoiceId,
        newInvoiceDate,
        newPaymentScheduledDate,
        newBillingAccountId,
        splitLines
      );
    } catch (Exception ex) {
      throw toAuraHandled(ex.getMessage());
    }
    return getInvoicePreview(contractHistoryId);
  }

  /**
   * 同一請求内の明細分割（単価／個数／月）。新請求は作らない。
   */
  @AuraEnabled
  public static InvoicePreviewDto splitLinesInPlace(
    Id contractHistoryId,
    Id invoiceId,
    List<InvoiceCanonicalService.SplitLineInput> splitLines,
    String expectedContentVersion
  ) {
    assertPreviewContentUnchanged(contractHistoryId, expectedContentVersion);
    try {
      InvoiceCanonicalService.splitLinesInPlace(invoiceId, splitLines);
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

  public static final String RESET_POST_ORDER_NON_LATEST_MESSAGE = '最新の受注 Version 以外は受注直後の請求に戻せません。';
  public static final String RESET_POST_ORDER_VERSION_REQUIRED_MESSAGE = 'Version を指定してください。';
  public static final String RESET_POST_ORDER_VERSION_NOT_FOUND_MESSAGE = '指定の Version の受注履歴が見つかりません。';

  /**
   * 最新 Ordered Version の請求／期間明細だけを受注直後相当へ作り直す。
   * 過去 Version は触らない。ロックがある Version は generate 側で拒否。
   */
  @AuraEnabled
  public static InvoicePreviewDto resetLatestVersionInvoicesToPostOrder(
    Id contractHistoryId,
    String versionValue,
    String expectedContentVersion
  ) {
    assertPreviewContentUnchanged(contractHistoryId, expectedContentVersion);
    try {
      InvoiceCanonicalService.assertCanEditInvoicePreview();
      Id targetHistoryId = resolveLatestOrderedHistoryIdForReset(
        contractHistoryId,
        versionValue
      );
      InvoiceProductGenerationService.generateForHistories(
        new Set<Id>{ targetHistoryId }
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

  /**
   * 利用月で分ける UI 用。請求明細の由来期間明細を月次候補として返す（保存は別途）。
   */
  public class PeriodSplitCandidateDto {
    @AuraEnabled
    public Id periodLineId;
    @AuraEnabled
    public Id invoiceLineId;
    @AuraEnabled
    public String productName;
    @AuraEnabled
    public String periodLabel;
    @AuraEnabled
    public Date startDate;
    @AuraEnabled
    public Date endDate;
    @AuraEnabled
    public Decimal amount;
  }

  @AuraEnabled
  public static List<PeriodSplitCandidateDto> getPeriodSplitCandidates(
    Id invoiceId
  ) {
    ContractPermissionUtil.assertViewInvoicePreview();
    List<PeriodSplitCandidateDto> rows = new List<PeriodSplitCandidateDto>();
    if (invoiceId == null) {
      return rows;
    }

    List<InvoiceLine__c> lines = [
      SELECT
        Id,
        Amount__c,
        ProductName__c,
        SourcePeriodLineIds__c
      FROM InvoiceLine__c
      WHERE Invoice__c = :invoiceId
      WITH SYSTEM_MODE
    ];
    if (lines.isEmpty()) {
      return rows;
    }

    Map<Id, Id> invoiceLineByPeriodId = new Map<Id, Id>();
    Map<Id, String> productNameByPeriodId = new Map<Id, String>();
    Map<Id, Decimal> lineAmountById = new Map<Id, Decimal>();
    Set<Id> periodIds = new Set<Id>();
    for (InvoiceLine__c line : lines) {
      lineAmountById.put(line.Id, line.Amount__c == null ? 0 : line.Amount__c);
      for (Id periodId : parseIdList(line.SourcePeriodLineIds__c)) {
        periodIds.add(periodId);
        invoiceLineByPeriodId.put(periodId, line.Id);
        productNameByPeriodId.put(periodId, line.ProductName__c);
      }
    }
    if (periodIds.isEmpty()) {
      return rows;
    }

    List<InvoiceProduct__c> periodLines = [
      SELECT
        Id,
        Amount__c,
        StartDate__c,
        Enddate__c,
        ContractProduct__r.Product__r.Name
      FROM InvoiceProduct__c
      WHERE Id IN :periodIds
      WITH SYSTEM_MODE
      ORDER BY StartDate__c ASC NULLS LAST, CreatedDate ASC
    ];

    // 明細ごとに由来期間合計を取り、表示金額＝明細金額×（期間÷合計）に按分する
    // （金額分割後も候補合計が請求明細税抜と一致するようにする）
    Map<Id, Decimal> periodSumByLineId = new Map<Id, Decimal>();
    for (InvoiceProduct__c periodLine : periodLines) {
      Id lineId = invoiceLineByPeriodId.get(periodLine.Id);
      if (lineId == null) {
        continue;
      }
      Decimal periodAmount = periodLine.Amount__c == null
        ? 0
        : periodLine.Amount__c;
      Decimal current = periodSumByLineId.containsKey(lineId)
        ? periodSumByLineId.get(lineId)
        : 0;
      periodSumByLineId.put(lineId, current + periodAmount);
    }

    Map<Id, Decimal> allocatedByLineId = new Map<Id, Decimal>();
    Map<Id, PeriodSplitCandidateDto> lastRowByLineId = new Map<Id, PeriodSplitCandidateDto>();
    for (InvoiceProduct__c periodLine : periodLines) {
      PeriodSplitCandidateDto row = new PeriodSplitCandidateDto();
      row.periodLineId = periodLine.Id;
      Id lineId = invoiceLineByPeriodId.get(periodLine.Id);
      row.invoiceLineId = lineId;
      String productName = periodLine.ContractProduct__r != null &&
        periodLine.ContractProduct__r.Product__r != null
        ? periodLine.ContractProduct__r.Product__r.Name
        : null;
      if (String.isBlank(productName)) {
        productName = productNameByPeriodId.get(periodLine.Id);
      }
      row.productName = productName;
      row.startDate = periodLine.StartDate__c;
      row.endDate = periodLine.Enddate__c;
      row.periodLabel = InvoiceProductMergeService.formatPeriod(
        periodLine.StartDate__c,
        periodLine.Enddate__c
      );
      Decimal periodAmount = periodLine.Amount__c == null
        ? 0
        : periodLine.Amount__c;
      Decimal lineAmount = lineId != null && lineAmountById.containsKey(lineId)
        ? lineAmountById.get(lineId)
        : 0;
      Decimal periodSum = lineId != null && periodSumByLineId.containsKey(lineId)
        ? periodSumByLineId.get(lineId)
        : 0;
      if (periodSum == 0) {
        row.amount = 0;
      } else {
        row.amount = (lineAmount * periodAmount / periodSum)
          .setScale(0, RoundingMode.HALF_UP);
      }
      rows.add(row);
      if (lineId != null) {
        Decimal allocated = allocatedByLineId.containsKey(lineId)
          ? allocatedByLineId.get(lineId)
          : 0;
        allocatedByLineId.put(lineId, allocated + row.amount);
        lastRowByLineId.put(lineId, row);
      }
    }
    // 按分の丸め差は最終行で吸収し、候補合計＝明細金額にする
    for (Id lineId : lastRowByLineId.keySet()) {
      PeriodSplitCandidateDto last = lastRowByLineId.get(lineId);
      Decimal lineAmount = lineAmountById.get(lineId);
      Decimal allocated = allocatedByLineId.get(lineId);
      if (last != null && lineAmount != null && allocated != null) {
        last.amount = last.amount + (lineAmount - allocated);
      }
    }
    return rows;
  }

  // 業務データはクライアントキャッシュ禁止（差し戻し判定は常に最新）
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
      option.invoiceAmountTotal = 0;
      option.amountDifference = 0;
      option.manualAdjustmentAmount = 0;
      options.add(option);
    }
    return options;
  }

  /**
   * Version フィルタ用に、見積（請求月数按分）・請求・ずれを Version 別に載せる。
   * 見積側は Ordered のみ（Archive / Estimate を混ぜない）。
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
      if (option.invoiceAmountTotal == null) {
        option.invoiceAmountTotal = 0;
      }
      if (option.manualAdjustmentAmount == null) {
        option.manualAdjustmentAmount = 0;
      }
      optionByValue.put(option.value, option);
    }

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

    for (InvoiceGroupDto invoice : preview.invoices) {
      if (invoice == null || invoice.historyVersion == null) {
        continue;
      }
      String value = String.valueOf(invoice.historyVersion.intValue());
      VersionOptionDto option = optionByValue.get(value);
      if (option == null) {
        continue;
      }
      Decimal amount = invoice.amountTotal == null ? 0 : invoice.amountTotal;
      option.invoiceAmountTotal =
        (option.invoiceAmountTotal == null ? 0 : option.invoiceAmountTotal) +
        amount;
    }

    for (VersionOptionDto option : preview.versionOptions) {
      Decimal periodTotal = option.periodLineAmountTotal == null
        ? 0
        : option.periodLineAmountTotal;
      Decimal invoiceTotal = option.invoiceAmountTotal == null
        ? 0
        : option.invoiceAmountTotal;
      option.amountDifference = invoiceTotal - periodTotal;
      if (option.manualAdjustmentAmount == null) {
        option.manualAdjustmentAmount = 0;
      }
    }
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
      return '受注済み（Ordered）状態の契約履歴のみ差し戻しできます。';
    }
    if (ContractPermissionUtil.canBypassIntegrityGuards()) {
      return null;
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
    if (
      EstimateRevertInvoiceService.hasNewerEstimateVersion(contractHistoryId)
    ) {
      return EstimateRevertInvoiceService.NEWER_ESTIMATE_REVERT_MESSAGE;
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
        '受注済み（Ordered）状態の契約履歴のみ差し戻しできます。'
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
      throw toAuraHandled(
        '見積（Estimate）状態の契約履歴のみ編集できます。'
      );
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

  private static ContractHistory__c resolveHistoryForPreview(Id contractHistoryId) {
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
    String editableFieldClause = buildOrderHistoryEditableFieldClause();
    String soql =
      'SELECT Id, Name, Type__c, historystatus__c, Version__c, LastModifiedDate, ' +
      'CurrentTermStartDate__c, CurrentTermEndDate__c, EffectiveDate__c' +
      editableFieldClause +
      ', ContractService__c, ContractService__r.Name, ContractService__r.Lifecycle__c, ' +
      'ContractService__r.Account__r.Name, ContractService__r.BiilingAcccount__c, ' +
      'ContractService__r.BiilingAcccount__r.Name, ' +
      'ContractService__r.BiilingAcccount__r.PaymentTerm__c, ' +
      'ContractService__r.BiilingAcccount__r.BillingDayOfMonth__c, ' +
      'ContractService__r.BiilingAcccount__r.AdjustInvoiceDateToBusinessDay__c, ' +
      'ContractService__r.BiilingAcccount__r.BillingAddressee__c, ' +
      'ContractService__r.BiilingAcccount__r.BillingEmailTo__c, ' +
      'ContractService__r.BiilingAcccount__r.BillingEmailCc__c, ' +
      'ContractService__r.BiilingAcccount__r.BillingEmailBcc__c, ' +
      'ContractService__r.BiilingAcccount__r.Account__r.Name ' +
      'FROM ContractHistory__c WHERE Id = :contractHistoryId LIMIT 1';
    return Database.queryWithBinds(
      soql,
      new Map<String, Object>{ 'contractHistoryId' => contractHistoryId },
      AccessLevel.SYSTEM_MODE
    );
  }

  private static List<ContractHistory__c> queryEstimateHistoryForEdit(
    Id contractHistoryId
  ) {
    String editableFieldClause = buildOrderHistoryEditableFieldClause();
    String soql =
      'SELECT Id, Type__c, historystatus__c, Version__c, ContractService__c, ' +
      'ContractService__r.Lifecycle__c, LastModifiedDate' +
      editableFieldClause +
      ' FROM ContractHistory__c WHERE Id = :contractHistoryId LIMIT 1';
    return Database.queryWithBinds(
      soql,
      new Map<String, Object>{ 'contractHistoryId' => contractHistoryId },
      AccessLevel.SYSTEM_MODE
    );
  }

  /**
   * Spot（都度）契約では更新商談を作らない。
   * Cancel / Add、Lifecycle=Spot、または Lifecycle 未確定かつ継続課金なし。
   */
  @TestVisible
  private static Boolean shouldSkipRenewOpportunity(ContractHistory__c history) {
    if (history == null) {
      return true;
    }
    if (
      history.Type__c == HISTORY_TYPE_CANCEL ||
      history.Type__c == HISTORY_TYPE_ADD
    ) {
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
      SELECT BillingType__c, Product__r.BillingType__c, Quantity__c
      FROM ContractProduct__c
      WHERE ContractHistory__c = :contractHistoryId AND Quantity__c > 0
      WITH SYSTEM_MODE
    ]) {
      String billingType = String.isNotBlank(product.BillingType__c)
        ? product.BillingType__c
        : product.Product__r.BillingType__c;
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
    ContractOptimisticLockUtil.assertUnchanged(
      resolvePreviewContentDatetime(contractServiceId),
      expectedContentVersion,
      '請求プレビュー'
    );
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
        PaymentTerm__c,
        BillingDayOfMonth__c,
        AdjustInvoiceDateToBusinessDay__c
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
    values.put('PaymentTerm__c', loaded.PaymentTerm__c);
    values.put('BillingDayOfMonth__c', loaded.BillingDayOfMonth__c);
    values.put(
      'AdjustInvoiceDateToBusinessDay__c',
      loaded.AdjustInvoiceDateToBusinessDay__c == true
    );
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

    List<Invoice__c> invoices = [
      SELECT
        Id,
        Name,
        MergeKey__c,
        InvoiceDate__c,
        PaymentScheduledDate__c,
        Amount__c,
        TaxAmount__c,
        TaxPercent__c,
        SystemIntegrationDate__c,
        PaymentClearingCompletedDate__c,
        PaymentClearedAmount__c,
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
        PaymentTermSnapShot__c,
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
      invoice.paymentTerm = invoiceRecord.PaymentTermSnapShot__c;
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
      InvoicePaymentStatusUtil.StatusAmounts statusAmounts = InvoicePaymentStatusUtil.resolveStatusAmounts(
        invoiceRecord,
        amountTotal
      );
      invoice.integratedAmount = statusAmounts.integratedAmount;
      invoice.clearedAmount = statusAmounts.clearedAmount;
      invoice.openAmount = statusAmounts.openAmount;
      invoice.lines = new List<InvoiceMergedLineDto>();

      invoiceTotal += amountTotal;
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
      preview.invoiceCount++;
      preview.totalAmount += amountTotal;
      preview.totalTaxAmount += taxTotal;
      preview.integratedAmount += invoice.integratedAmount;
      preview.clearedAmount += invoice.clearedAmount;
      preview.openAmount += invoice.openAmount;
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
        Decimal versionLineAmount = lineAmountByVersion.containsKey(versionValue)
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
        sumSourceAmounts(sourceIdsByVersion.get(versionValue), sourceAmountById);
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
    Integer cpCycles = resolveCpCycles(product);
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
    Decimal scopedEstimate = prorateEstimateByMonths(
      estimate,
      totalMonths,
      cpCycles
    );
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
        lineEstimate = (scopedEstimate * lineWeight / totalWeight)
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
        lineEstimate = (scopedEstimate * lineAmount / invoiceTotal)
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
   * Ordered CP.Amount を請求生成月数で按分した見積合計。
   * 継続: Amount × (IP件数 / CP月数)。一回: IP が1件以上あれば Amount 全額。
   */
  private static ScopedEstimateSummary buildScopedEstimateSummary(
    Id contractServiceId
  ) {
    ScopedEstimateSummary summary = new ScopedEstimateSummary();
    if (contractServiceId == null) {
      return summary;
    }

    List<ContractProduct__c> products = [
      SELECT
        Id,
        Amount__c,
        BillingType__c,
        StartDate__c,
        Enddate__c,
        ContractHistory__r.Version__c
      FROM ContractProduct__c
      WHERE
        ContractHistory__r.ContractService__c = :contractServiceId
        AND ContractHistory__r.historystatus__c = :HISTORY_STATUS_ORDERED
      WITH SYSTEM_MODE
    ];
    if (products.isEmpty()) {
      return summary;
    }

    Set<Id> contractProductIds = new Set<Id>();
    for (ContractProduct__c product : products) {
      contractProductIds.add(product.Id);
    }

    Map<Id, Integer> invoicedMonthsByCp = new Map<Id, Integer>();
    for (AggregateResult ar : [
      SELECT ContractProduct__c cpId, COUNT(Id) cnt
      FROM InvoiceProduct__c
      WHERE ContractProduct__c IN :contractProductIds
      WITH SYSTEM_MODE
      GROUP BY ContractProduct__c
    ]) {
      invoicedMonthsByCp.put((Id) ar.get('cpId'), (Integer) ar.get('cnt'));
    }

    for (ContractProduct__c product : products) {
      Decimal amount = product.Amount__c == null ? 0 : product.Amount__c;
      Integer invoicedMonths = invoicedMonthsByCp.containsKey(product.Id)
        ? invoicedMonthsByCp.get(product.Id)
        : 0;
      Decimal scoped;
      if (ContractMetadataService.isRecurringBillingType(product.BillingType__c)) {
        scoped = prorateEstimateByMonths(
          amount,
          invoicedMonths,
          resolveCpCycles(product)
        );
      } else {
        scoped = invoicedMonths > 0 ? amount : 0;
      }
      summary.total += scoped;

      Decimal version = product.ContractHistory__r == null
        ? null
        : product.ContractHistory__r.Version__c;
      if (version == null) {
        continue;
      }
      String value = String.valueOf(version.intValue());
      Decimal current = summary.byVersion.containsKey(value)
        ? summary.byVersion.get(value)
        : 0;
      summary.byVersion.put(value, current + scoped);
    }
    return summary;
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

  private static Decimal prorateEstimateByMonths(
    Decimal amount,
    Integer months,
    Integer cpCycles
  ) {
    Decimal estimate = amount == null ? 0 : amount;
    Integer cycles = cpCycles == null || cpCycles < 1 ? 1 : cpCycles;
    Integer monthCount = months == null || months < 0 ? 0 : months;
    if (monthCount < 1) {
      return 0;
    }
    return (estimate * monthCount / cycles)
      .setScale(0, System.RoundingMode.HALF_UP);
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
    preview.invoiceAmountTotal = 0;
    preview.amountDifference = 0;
    preview.manualAdjustmentAmount = 0;
    preview.hasManualAdjustment = false;
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