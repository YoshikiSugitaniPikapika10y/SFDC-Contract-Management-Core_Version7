/**
 * Estimate read/query/preset APIs used by LWC via EstimateCreateController.
 */
public without sharing class EstimateQueryService {
  private static final String HISTORY_STATUS_ESTIMATE = ContractDomainConstants.HISTORY_STATUS_ESTIMATE;
  private static final String HISTORY_STATUS_ARCHIVE = ContractDomainConstants.HISTORY_STATUS_ARCHIVE;
  private static final String HISTORY_STATUS_ORDERED = ContractDomainConstants.HISTORY_STATUS_ORDERED;
  private static final String HISTORY_TYPE_NEW = ContractDomainConstants.HISTORY_TYPE_NEW;
  private static final String HISTORY_TYPE_CHANGE = ContractDomainConstants.HISTORY_TYPE_CHANGE;
  private static final String HISTORY_TYPE_RENEW = ContractDomainConstants.HISTORY_TYPE_RENEW;
  private static final String HISTORY_TYPE_CANCEL = ContractDomainConstants.HISTORY_TYPE_CANCEL;
  private static final String LEGACY_HISTORY_TYPE_ADD = 'Add';
  private static final String BILLING_TYPE_RECURRING = ContractDomainConstants.BILLING_TYPE_RECURRING;
  private static final String BILLING_TYPE_ONE_TIME = ContractDomainConstants.BILLING_TYPE_ONE_TIME;
  private static final String MONTHLY_BILLING_CYCLE = ContractDomainConstants.MONTHLY_BILLING_CYCLE;
  private static final String PRODUCT_TYPE_ORIGINAL = ContractDomainConstants.PRODUCT_TYPE_ORIGINAL;
  private static final String PRODUCT_TYPE_REMAKE = ContractDomainConstants.PRODUCT_TYPE_REMAKE;
  private static final String LEGACY_PRODUCT_TYPE_DERIVATIVE = ContractDomainConstants.LEGACY_PRODUCT_TYPE_DERIVATIVE;
  private static final String PRODUCT_TYPE_NEW = ContractDomainConstants.PRODUCT_TYPE_NEW;
  private static final String PRODUCT_TYPE_RENEW = ContractDomainConstants.PRODUCT_TYPE_RENEW;
  private static final Integer NOTE_MAX_LENGTH = ContractDomainConstants.NOTE_MAX_LENGTH;
  private static Map<Id, ContractHistory__c> latestOrderedByServiceId = new Map<Id, ContractHistory__c>();
  private static Set<Id> latestOrderedQueriedServiceIds = new Set<Id>();

  /** 継続課金の正は明細 BillingType。商品マスタへ戻さない。 */
  private static String recurringLineSoqlPredicate() {
    return 'BillingType__c = :BILLING_TYPE_RECURRING';
  }

  public static List<EstimateCreateController.ContractProductLineDto> getRecurringContractProducts(
    Id contractHistoryId
  ) {
    if (contractHistoryId == null) {
      return new List<EstimateCreateController.ContractProductLineDto>();
    }

    String soql =
      'SELECT ' +
      String.join(buildContractProductLineSelectFields(), ',') +
      ' FROM ContractProduct__c' +
      ' WHERE ContractHistory__c = :contractHistoryId' +
      ' AND ' +
      recurringLineSoqlPredicate() +
      ' AND Quantity__c > 0' +
      ' AND (' +
      ' Type__c = NULL' +
      ' OR Type__c IN (' +
      ' :PRODUCT_TYPE_REMAKE,' +
      ' :PRODUCT_TYPE_NEW,' +
      ' :PRODUCT_TYPE_RENEW' +
      ' )' +
      ' )' +
      ' WITH SYSTEM_MODE' +
      ' ORDER BY Name ASC';
    List<ContractProduct__c> products = Database.query(soql);
    return toContractProductLineDtos(products);
  }

  public static List<EstimateCreateController.ContractProductLineDto> getRenewContractProducts(
    Id contractServiceId
  ) {
    if (contractServiceId == null) {
      return new List<EstimateCreateController.ContractProductLineDto>();
    }

    ContractHistory__c sourceHistory = queryLatestActiveOrderedHistory(
      contractServiceId
    );
    if (
      sourceHistory == null ||
      sourceHistory.CurrentTermEndDate__c == null ||
      sourceHistory.Type__c == HISTORY_TYPE_CANCEL
    ) {
      return new List<EstimateCreateController.ContractProductLineDto>();
    }

    Date termEndDate = sourceHistory.CurrentTermEndDate__c;
    Id sourceHistoryId = sourceHistory.Id;

    String soql =
      'SELECT ' +
      String.join(buildContractProductLineSelectFields(), ',') +
      ' FROM ContractProduct__c' +
      ' WHERE ContractHistory__c = :sourceHistoryId' +
      ' AND ' +
      recurringLineSoqlPredicate() +
      ' AND Quantity__c > 0' +
      ' AND Enddate__c = :termEndDate' +
      ' AND (' +
      ' Type__c = NULL' +
      ' OR Type__c IN (' +
      ' :PRODUCT_TYPE_REMAKE,' +
      ' :PRODUCT_TYPE_NEW,' +
      ' :PRODUCT_TYPE_RENEW' +
      ' )' +
      ' )' +
      ' WITH SYSTEM_MODE' +
      ' ORDER BY Name ASC';
    List<ContractProduct__c> products = Database.query(soql);
    return toContractProductLineDtos(products);
  }

  public static List<String> buildContractProductLineSelectFields() {
    List<String> selectFields = new List<String>{
      'Id',
      'Product__c',
      'Product__r.Name',
      'Product__r.UnitName__c',
      'Product__r.BillingType__c',
      'Product__r.RevenueRecognitionBasis__c',
      'Unit__c',
      'UnitPrice__c',
      'Quantity__c',
      'Amount__c',
      'BillingType__c',
      'RevenueRecognitionBasis__c',
      'Type__c',
      'StartDate__c',
      'Enddate__c',
      'InvoiceSetting__c',
      'InvoiceAnchorDate__c',
      'InvoiceBillingCycleCount__c'
    };
    for (
      String relationshipField : ContractWizardFieldService.getProduct2RelationshipSelectFields(
        'Product__r'
      )
    ) {
      if (!selectFields.contains(relationshipField)) {
        selectFields.add(relationshipField);
      }
    }
    for (
      String apiName : ContractWizardFieldService.getActiveFieldApiNames(
        ContractWizardFieldService.WizardTarget.ContractProduct
      )
    ) {
      if (!selectFields.contains(apiName)) {
        selectFields.add(apiName);
      }
    }
    return selectFields;
  }

  /** 仕様: Core 第4.5.2節、第1.1.10節。Change／Renew 継承元の単位は保存値のまま。商品マスタから埋めない。 */
  public static List<EstimateCreateController.ContractProductLineDto> toContractProductLineDtos(
    List<ContractProduct__c> products
  ) {
    List<EstimateCreateController.ContractProductLineDto> lines = new List<EstimateCreateController.ContractProductLineDto>();
    for (ContractProduct__c product : products) {
      String billingType = ContractMetadataService.resolveLineBillingType(
        product
      );
      EstimateCreateController.ContractProductLineDto line = new EstimateCreateController.ContractProductLineDto();
      line.contractProductId = product.Id;
      line.productId = product.Product__c;
      line.productName = product.Product__r.Name;
      line.unitName = product.Product__r.UnitName__c;
      line.billingType = billingType;
      line.billingCycle = EstimateCreateSupport.resolveRecurringBillingCycleLabel(
        billingType
      );
      line.revenueRecognitionBasis = ContractMetadataService.resolveLineRevenueRecognitionBasis(
        product
      );
      line.unit = product.Unit__c;
      line.unitPrice = product.UnitPrice__c;
      line.quantity = product.Quantity__c;
      line.amount = product.Amount__c;
      if (line.amount == null) {
        line.amount = ContractProductAmountUtil.calculateSignedAmount(
          product,
          billingType
        );
      }
      line.startDate = EstimateCreateSupport.formatDate(product.StartDate__c);
      line.endDate = EstimateCreateSupport.formatDate(product.Enddate__c);
      line.invoiceType = ContractMetadataService.normalizeInvoiceSettingLabel(
        product.InvoiceSetting__c
      );
      line.customFields = ContractWizardFieldService.extractCustomFields(
        product,
        ContractWizardFieldService.WizardTarget.ContractProduct
      );
      line.productVisibilityContext = ContractWizardFieldService.buildProductVisibilityContext(
        product.Product__r
      );
      lines.add(line);
    }
    return lines;
  }

  public static EstimateCreateController.ContractHistoryDto getLatestContractHistory(
    Id contractServiceId
  ) {
    if (contractServiceId == null) {
      return null;
    }

    ContractHistory__c history = queryLatestActiveOrderedHistory(
      contractServiceId
    );
    if (history == null) {
      return null;
    }

    EstimateCreateController.ContractHistoryDto dto = toContractHistoryDto(
      history
    );
    // 仕様: Core 第4.3節。コピー／新規表示の Version は最新 Ordered + 1。同一処理の最新 Ordered を再利用する。
    Decimal latestVersion = history.Version__c;
    dto.nextVersion = latestVersion == null ? 1 : latestVersion + 1;
    return dto;
  }

  public static ContractHistory__c queryLatestActiveOrderedHistory(
    Id contractServiceId
  ) {
    if (contractServiceId == null) {
      return null;
    }
    if (latestOrderedQueriedServiceIds.contains(contractServiceId)) {
      return latestOrderedByServiceId.get(contractServiceId);
    }
    latestOrderedQueriedServiceIds.add(contractServiceId);

    List<ContractHistory__c> histories = [
      SELECT
        Id,
        Name,
        Version__c,
        Type__c,
        ContractService__c,
        CurrentTermStartDate__c,
        CurrentTermEndDate__c,
        EstimateSendContact__c
      FROM ContractHistory__c
      WHERE
        ContractService__c = :contractServiceId
        AND historystatus__c = :HISTORY_STATUS_ORDERED
        AND Type__c IN (
          :HISTORY_TYPE_NEW,
          :HISTORY_TYPE_CHANGE,
          :HISTORY_TYPE_RENEW,
          :HISTORY_TYPE_CANCEL,
          :LEGACY_HISTORY_TYPE_ADD
        )
      WITH SYSTEM_MODE
      ORDER BY Version__c DESC NULLS LAST
      LIMIT 1
    ];
    if (histories.isEmpty()) {
      return null;
    }

    latestOrderedByServiceId.put(contractServiceId, histories[0]);
    return histories[0];
  }

  public static EstimateCreateController.ContractHistoryDto getContractHistoryInfo(
    Id contractHistoryId
  ) {
    if (contractHistoryId == null) {
      return null;
    }

    List<ContractHistory__c> histories = [
      SELECT
        Id,
        Name,
        Version__c,
        Type__c,
        CurrentTermStartDate__c,
        CurrentTermEndDate__c,
        EstimateSendContact__c
      FROM ContractHistory__c
      WHERE Id = :contractHistoryId
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    if (histories.isEmpty()) {
      return null;
    }

    return toContractHistoryDto(histories[0]);
  }

  public static EstimateCreateController.EstimateCopyPresetDto getEstimateCopyPreset(
    Id contractHistoryId
  ) {
    return buildEstimatePreset(contractHistoryId, false);
  }

  public static EstimateCreateController.EstimateCopyPresetDto getEstimateEditPreset(
    Id contractHistoryId
  ) {
    return buildEstimatePreset(contractHistoryId, true);
  }

  /** 仕様: Core 第4.7節・第0.1節。コピー元はEstimateだけ。Archiveは編集できない。人が見る拒否文は日本語で返す。 */
  public static EstimateCreateController.EstimateCopyPresetDto buildEstimatePreset(
    Id contractHistoryId,
    Boolean forEdit
  ) {
    String actionLabel = forEdit == true ? '編集' : 'コピー';
    if (contractHistoryId == null) {
      throw EstimateValidationService.wrapAura(
        actionLabel + '元の契約履歴が指定されていません。'
      );
    }

    List<String> historySelectFields = new List<String>{
      'Id',
      'Name',
      'Type__c',
      'Version__c',
      'historystatus__c',
      'CurrentTermStartDate__c',
      'CurrentTermEndDate__c',
      'EffectiveDate__c',
      'Opportunity__c',
      'Opportunity__r.Name',
      'Opportunity__r.Account.Name',
      'ContractService__c',
      'EstimateNoteMaster__c',
      'Note__c',
      'EstimateDate__c',
      'EstimateValidDate__c',
      'EstimateSendContact__c',
      'PreviousHistory__c',
      'PreviousHistory__r.Name',
      'PreviousHistory__r.Version__c',
      'PreviousHistory__r.CurrentTermStartDate__c',
      'PreviousHistory__r.CurrentTermEndDate__c',
      'LastModifiedDate'
    };
    for (
      String apiName : ContractWizardFieldService.getActiveFieldApiNames(
        ContractWizardFieldService.WizardTarget.ContractHistory
      )
    ) {
      if (!historySelectFields.contains(apiName)) {
        historySelectFields.add(apiName);
      }
    }
    String historySoql =
      'SELECT ' +
      String.join(historySelectFields, ',') +
      ' FROM ContractHistory__c' +
      ' WHERE Id = :contractHistoryId' +
      ' WITH SYSTEM_MODE' +
      ' LIMIT 1';
    List<ContractHistory__c> histories = Database.query(historySoql);

    if (histories.isEmpty()) {
      throw EstimateValidationService.wrapAura('契約履歴が見つかりません。');
    }

    ContractHistory__c history = histories[0];
    if (forEdit == true) {
      if (
        history.historystatus__c != HISTORY_STATUS_ESTIMATE &&
        history.historystatus__c != HISTORY_STATUS_ORDERED
      ) {
        throw EstimateValidationService.wrapAura(
          '見積／受注済み状態の契約履歴のみ編集できます。'
        );
      }
    } else if (history.historystatus__c != HISTORY_STATUS_ESTIMATE) {
      throw EstimateValidationService.wrapAura(
        '見積状態の契約履歴のみ' + actionLabel + 'できます。'
      );
    }
    if (history.Opportunity__c == null) {
      throw EstimateValidationService.wrapAura('商談が設定されていません。');
    }

    EstimateCreateController.EstimateCopyPresetDto preset = new EstimateCreateController.EstimateCopyPresetDto();
    preset.historyStatus = history.historystatus__c;
    List<ContractProduct__c> copyProducts = queryCopyProducts(history.Id);
    preset.lastModifiedToken = copyPresetToken(
      history.LastModifiedDate,
      copyProducts
    );
    preset.opportunityId = history.Opportunity__c;
    preset.opportunityName = history.Opportunity__r.Name;
    preset.accountName = history.Opportunity__r.Account == null
      ? ''
      : history.Opportunity__r.Account.Name;
    preset.selectedType = history.Type__c;
    // 仕様: Core 第4.3.3節、第4.7節、第0.1節。コピーに「のコピー」を付けない。
    preset.contractHistoryName = forEdit == true
      ? history.Name
      : resolveCopyHistoryName(history);
    preset.contractStartDate = EstimateCreateSupport.formatDate(
      history.CurrentTermStartDate__c
    );
    String termEnd = EstimateCreateSupport.formatDate(
      history.CurrentTermEndDate__c
    );
    preset.endDate = termEnd;
    preset.contractEndDate = termEnd;
    // 仕様: Core 第1.1.10節、第4.7節。空の切替日を開始日で埋めない。
    preset.contractEffectiveDate = EstimateCreateSupport.formatDate(
      history.EffectiveDate__c
    );
    preset.estimateRemarkMasterId = history.EstimateNoteMaster__c;
    preset.estimateRemarks = history.Note__c == null ? '' : history.Note__c;
    preset.estimateDate = EstimateCreateSupport.formatDate(
      history.EstimateDate__c
    );
    preset.estimateValidDate = EstimateCreateSupport.formatDate(
      history.EstimateValidDate__c
    );
    preset.estimateSendContactId = history.EstimateSendContact__c;
    preset.selectedProducts = toCopyProductLineItems(
      copyProducts,
      history.Type__c
    );
    preset.contractHistoryCustomFields = ContractWizardFieldService.extractCustomFields(
      history,
      ContractWizardFieldService.WizardTarget.ContractHistory
    );
    // 仕様: Core 第4.3節、第11.4.3節
    if (
      forEdit == true &&
      history.historystatus__c == HISTORY_STATUS_ORDERED
    ) {
      if (preset.contractHistoryCustomFields == null) {
        preset.contractHistoryCustomFields = new Map<String, Object>();
      }
      try {
        preset.contractHistoryCustomFields.putAll(
          OrderWizardFieldService.querySavedHistoryFieldValues(history.Id)
        );
      } catch (OrderWizardFieldService.WizardFieldConfigException ex) {
        throw EstimateValidationService.wrapAura(ex.getMessage());
      }
    }

    ContractService__c service = loadContractServiceForCopy(
      history.ContractService__c
    );
    preset.contractServiceCustomFields = ContractWizardFieldService.extractCustomFields(
      service,
      ContractWizardFieldService.WizardTarget.ContractService
    );
    // 仕様: 契約のカスタム項目パネルはデフォルト開（値の有無で閉じない）
    preset.contractCustomFieldsExpanded = true;
    if (service != null) {
      preset.serviceLifecycle = service.Lifecycle__c;
      preset.taxPercent = TaxCalculationUtil.fromPercentFieldStorage(
        service.TaxPercent__c
      );
    }

    if (history.Type__c == 'New') {
      if (forEdit == true) {
        preset.contractServiceName = service == null ? '' : service.Name;
        preset.contractServiceId = history.ContractService__c;
        preset.nextHistoryVersion = history.Version__c;
      } else {
        preset.contractServiceName = service == null
          ? ''
          : buildCopyHistoryName(service.Name);
        preset.contractServiceId = null;
        // New コピーは契約サービスを新規化するため Lifecycle は載せない
        preset.serviceLifecycle = null;
      }
      preset.contractHistoryId = null;
      preset.billingAccountId = service == null
        ? null
        : service.BiilingAcccount__c;
      return preset;
    }

    preset.contractServiceId = history.ContractService__c;
    preset.contractHistoryId = history.PreviousHistory__c;
    preset.contractServiceName = service == null ? '' : service.Name;
    preset.billingAccountId = service == null
      ? null
      : service.BiilingAcccount__c;

    if (history.PreviousHistory__c != null) {
      preset.autoHistoryName = history.PreviousHistory__r.Name;
      preset.baseHistoryVersion = history.PreviousHistory__r.Version__c;
      preset.previousTermStartDate = EstimateCreateSupport.formatDate(
        history.PreviousHistory__r.CurrentTermStartDate__c
      );
      preset.previousTermEndDate = EstimateCreateSupport.formatDate(
        history.PreviousHistory__r.CurrentTermEndDate__c
      );
      if (forEdit == true) {
        preset.renewEligible =
          countRenewSourceRecurringProducts(
            history.PreviousHistory__c,
            history.PreviousHistory__r.CurrentTermEndDate__c
          ) > 0;
      }
    }

    EstimateCreateController.ContractHistoryDto latestHistory = getLatestContractHistory(
      history.ContractService__c
    );
    if (latestHistory != null) {
      if (String.isBlank(preset.autoHistoryName)) {
        preset.autoHistoryName = latestHistory.historyName;
      }
      if (preset.baseHistoryVersion == null) {
        preset.baseHistoryVersion = latestHistory.version;
      }
      if (forEdit != true || preset.renewEligible == null) {
        preset.renewEligible = latestHistory.renewEligible;
      }
    }

    // 編集は既存 Version を維持。コピー／新規表示は最新 Ordered + 1。
    if (forEdit == true) {
      preset.nextHistoryVersion = history.Version__c;
    } else if (latestHistory != null && latestHistory.nextVersion != null) {
      preset.nextHistoryVersion = latestHistory.nextVersion;
    } else {
      preset.nextHistoryVersion = ContractHistoryVersionUtil.getNextHistoryVersion(
        history.ContractService__c
      );
    }

    return preset;
  }

  public static ContractService__c loadContractServiceForCopy(
    Id contractServiceId
  ) {
    if (contractServiceId == null) {
      return null;
    }

    SObject loaded = loadRecordWithWizardFields(
      contractServiceId,
      ContractService__c.SObjectType,
      ContractWizardFieldService.WizardTarget.ContractService,
      new List<String>{
        'Id',
        'Name',
        'BiilingAcccount__c',
        'Lifecycle__c',
        'TaxPercent__c'
      }
    );
    return loaded == null ? null : (ContractService__c) loaded;
  }

  public static SObject loadRecordWithWizardFields(
    Id recordId,
    Schema.SObjectType sobjectType,
    ContractWizardFieldService.WizardTarget target
  ) {
    return loadRecordWithWizardFields(
      recordId,
      sobjectType,
      target,
      new List<String>{ 'Id' }
    );
  }

  public static SObject loadRecordWithWizardFields(
    Id recordId,
    Schema.SObjectType sobjectType,
    ContractWizardFieldService.WizardTarget target,
    List<String> baseFields
  ) {
    if (recordId == null || sobjectType == null) {
      return null;
    }

    Set<String> selectFields = new Set<String>();
    if (baseFields != null) {
      for (String fieldName : baseFields) {
        if (String.isNotBlank(fieldName)) {
          selectFields.add(fieldName);
        }
      }
    }
    selectFields.add('Id');
    selectFields.addAll(
      ContractWizardFieldService.getActiveFieldApiNames(target)
    );

    List<String> orderedFields = new List<String>(selectFields);
    orderedFields.sort();
    String soql =
      'SELECT ' +
      String.join(orderedFields, ',') +
      ' FROM ' +
      sobjectType.getDescribe().getName() +
      ' WHERE Id = :recordId WITH SYSTEM_MODE LIMIT 1';
    List<SObject> rows = Database.query(soql);
    return rows.isEmpty() ? null : rows[0];
  }

  public static Boolean hasCustomFieldMapValues(Map<String, Object> values) {
    if (values == null || values.isEmpty()) {
      return false;
    }
    for (Object value : values.values()) {
      if (value == null) {
        continue;
      }
      if (value instanceof String && String.isBlank((String) value)) {
        continue;
      }
      return true;
    }
    return false;
  }

  public static Boolean hasProductCustomFieldValues(
    List<EstimateCreateController.ProductLineItem> products
  ) {
    if (products == null) {
      return false;
    }
    for (EstimateCreateController.ProductLineItem line : products) {
      if (line != null && hasCustomFieldMapValues(line.customFields)) {
        return true;
      }
    }
    return false;
  }

  public static String buildCopyHistoryName(String sourceName) {
    String baseName = String.isBlank(sourceName) ? '' : sourceName.trim();
    return baseName + 'のコピー';
  }

  /** 仕様: Core 第4.3.3節、第4.7節、第0.1節 */
  private static String resolveCopyHistoryName(ContractHistory__c history) {
    if (history == null) {
      return '';
    }
    if (
      history.Type__c == HISTORY_TYPE_CHANGE ||
      history.Type__c == HISTORY_TYPE_RENEW
    ) {
      return '';
    }
    if (history.Type__c == HISTORY_TYPE_CANCEL) {
      String baseName = history.PreviousHistory__r == null
        ? ''
        : history.PreviousHistory__r.Name;
      return buildCancelHistoryName(baseName);
    }
    return history.Name == null ? '' : history.Name;
  }

  /** 仕様: Core 第4.3.3節、第0.1節 */
  private static String buildCancelHistoryName(String sourceName) {
    String baseName = String.isBlank(sourceName) ? '' : sourceName.trim();
    if (String.isBlank(baseName)) {
      return '';
    }
    if (baseName.endsWith('解約')) {
      return baseName;
    }
    return baseName + ' 解約';
  }

  public static List<EstimateCreateController.ProductLineItem> loadCopyProductLines(
    Id contractHistoryId,
    String selectedType
  ) {
    return toCopyProductLineItems(
      queryCopyProducts(contractHistoryId),
      selectedType
    );
  }

  /** 仕様: Core 第4.3.12節。コピー初期値と版トークンで同一の見積商品照会を使う。 */
  private static List<ContractProduct__c> queryCopyProducts(Id contractHistoryId) {
    List<String> selectFields = new List<String>{
      'Id',
      'LastModifiedDate',
      'Product__c',
      'Product__r.Name',
      'Product__r.UnitName__c',
      'Product__r.BillingType__c',
      'Product__r.RevenueRecognitionBasis__c',
      'Unit__c',
      'UnitPrice__c',
      'Quantity__c',
      'StartDate__c',
      'Enddate__c',
      'InvoiceSetting__c',
      'BillingType__c',
      'RevenueRecognitionBasis__c',
      'Type__c',
      'Amount__c',
      'PreviousContractProduct__c'
    };
    for (
      String relationshipField : ContractWizardFieldService.getProduct2RelationshipSelectFields(
        'Product__r'
      )
    ) {
      if (!selectFields.contains(relationshipField)) {
        selectFields.add(relationshipField);
      }
    }
    for (
      String apiName : ContractWizardFieldService.getActiveFieldApiNames(
        ContractWizardFieldService.WizardTarget.ContractProduct
      )
    ) {
      if (!selectFields.contains(apiName)) {
        selectFields.add(apiName);
      }
    }

    String soql =
      'SELECT ' +
      String.join(selectFields, ',') +
      ' FROM ContractProduct__c' +
      ' WHERE ContractHistory__c = :contractHistoryId' +
      ' WITH SYSTEM_MODE' +
      ' ORDER BY Name ASC';
    List<ContractProduct__c> products = Database.query(soql);
    return products;
  }

  private static List<EstimateCreateController.ProductLineItem> toCopyProductLineItems(
    List<ContractProduct__c> products,
    String selectedType
  ) {
    Map<Id, String> pairIdBySource = new Map<Id, String>();
    Integer pairIndex = 0;
    for (ContractProduct__c product : products) {
      Id pairKey = product.PreviousContractProduct__c != null
        ? product.PreviousContractProduct__c
        : product.Id;
      if (!pairIdBySource.containsKey(pairKey)) {
        pairIndex++;
        pairIdBySource.put(pairKey, 'pair-' + pairIndex);
      }
    }

    List<EstimateCreateController.ProductLineItem> lines = new List<EstimateCreateController.ProductLineItem>();
    for (ContractProduct__c product : products) {
      lines.add(toCopyProductLineItem(product, selectedType, pairIdBySource));
    }
    return lines;
  }

  /** 仕様: Core 第4.3.12節。同一処理で読んだ見積商品の最終更新を再利用する。 */
  public static String copyPresetToken(
    Datetime historyLastModified,
    List<ContractProduct__c> products
  ) {
    Datetime maxLm = historyLastModified;
    if (products != null) {
      for (ContractProduct__c product : products) {
        if (
          product != null &&
          product.LastModifiedDate != null &&
          (maxLm == null || product.LastModifiedDate > maxLm)
        ) {
          maxLm = product.LastModifiedDate;
        }
      }
    }
    return ContractOptimisticLockUtil.toToken(maxLm);
  }

  /** 仕様: Core 第4.5.2節、第4.7節、第1.1.10節。Original／Remake／Renew の空単位を商品マスタから埋めない。 */
  public static EstimateCreateController.ProductLineItem toCopyProductLineItem(
    ContractProduct__c product,
    String selectedType,
    Map<Id, String> pairIdBySource
  ) {
    String billingType = ContractMetadataService.resolveLineBillingType(
      product
    );
    String recordType = EstimateCreateSupport.normalizeProductRecordType(
      product.Type__c
    );

    EstimateCreateController.ProductLineItem line = new EstimateCreateController.ProductLineItem();
    line.contractProductId = product.Id;
    line.productId = product.Product__c;
    line.productName = product.Product__r.Name;
    line.quantity = product.Quantity__c;
    line.unitPrice = product.UnitPrice__c;
    line.startDate = EstimateCreateSupport.formatDate(product.StartDate__c);
    line.endDate = EstimateCreateSupport.formatDate(product.Enddate__c);
    line.invoiceType = ContractMetadataService.resolveInvoiceSettingForBillingType(
      billingType,
      product.InvoiceSetting__c
    );
    line.unitName = product.Product__r != null
      ? product.Product__r.UnitName__c
      : null;
    // 仕様: Core 第4.5.2節、第4.7節、第1.1.10節。Original／Remake／Renew の空単位を商品マスタから埋めない。
    Boolean keepSavedUnitSnapshot =
      recordType == PRODUCT_TYPE_ORIGINAL ||
      recordType == PRODUCT_TYPE_REMAKE ||
      recordType == PRODUCT_TYPE_RENEW;
    line.unit = keepSavedUnitSnapshot || String.isNotBlank(product.Unit__c)
      ? product.Unit__c
      : EstimateCreateSupport.buildDisplayUnit(line.unitName, billingType);
    line.billingType = billingType;
    line.billingCycle = EstimateCreateSupport.resolveRecurringBillingCycleLabel(
      billingType
    );
    line.revenueRecognitionBasis = ContractMetadataService.resolveLineRevenueRecognitionBasis(
      product
    );
    line.recordType = recordType;
    line.typeLabel = resolveCopyTypeLabel(recordType);
    line.isDuplicate = false;
    line.sourceContractProductId = product.PreviousContractProduct__c;
    line.isReadonly = recordType == PRODUCT_TYPE_ORIGINAL;
    line.amount = product.Amount__c;
    if (line.amount == null) {
      line.amount = ContractProductAmountUtil.calculateSignedAmount(
        product,
        billingType
      );
    }
    line.customFields = recordType == PRODUCT_TYPE_ORIGINAL
      ? new Map<String, Object>()
      : ContractWizardFieldService.extractCustomFields(
          product,
          ContractWizardFieldService.WizardTarget.ContractProduct
        );
    line.productVisibilityContext = ContractWizardFieldService.buildProductVisibilityContext(
      product.Product__r
    );

    Id pairKey = product.PreviousContractProduct__c != null
      ? product.PreviousContractProduct__c
      : product.Id;
    if (selectedType == 'Change' && pairIdBySource.containsKey(pairKey)) {
      line.pairId = pairIdBySource.get(pairKey);
    }

    return line;
  }

  public static String resolveCopyTypeLabel(String recordType) {
    if (recordType == PRODUCT_TYPE_ORIGINAL) {
      return 'Original';
    }
    if (recordType == PRODUCT_TYPE_REMAKE) {
      return 'Remake';
    }
    if (recordType == LEGACY_PRODUCT_TYPE_DERIVATIVE) {
      return 'Remake';
    }
    if (recordType == PRODUCT_TYPE_RENEW) {
      return 'Renew';
    }
    return 'New';
  }

  public static EstimateCreateController.ContractHistoryDto toContractHistoryDto(
    ContractHistory__c history
  ) {
    EstimateCreateController.ContractHistoryDto dto = new EstimateCreateController.ContractHistoryDto();
    dto.historyId = history.Id;
    dto.historyName = history.Name;
    dto.version = history.Version__c;
    dto.termStartDate = EstimateCreateSupport.formatDate(
      history.CurrentTermStartDate__c
    );
    dto.termEndDate = EstimateCreateSupport.formatDate(
      history.CurrentTermEndDate__c
    );
    dto.historyType = history.Type__c;
    dto.renewEligible = isRenewEligibleHistory(history);
    dto.estimateSendContactId = history.EstimateSendContact__c;
    return dto;
  }

  public static Boolean isRenewEligibleHistory(ContractHistory__c history) {
    if (
      history == null ||
      history.Id == null ||
      history.Type__c == HISTORY_TYPE_CANCEL ||
      history.CurrentTermEndDate__c == null
    ) {
      return false;
    }
    return countRenewSourceRecurringProducts(
        history.Id,
        history.CurrentTermEndDate__c
      ) > 0;
  }

  public static Integer countRenewSourceRecurringProducts(
    Id contractHistoryId,
    Date termEndDate
  ) {
    if (contractHistoryId == null || termEndDate == null) {
      return 0;
    }

    return [
      SELECT COUNT()
      FROM ContractProduct__c
      WHERE
        ContractHistory__c = :contractHistoryId
        AND BillingType__c = :BILLING_TYPE_RECURRING
        AND Quantity__c > 0
        AND Enddate__c = :termEndDate
        AND (Type__c = NULL
        OR Type__c IN (
          :PRODUCT_TYPE_REMAKE,
          :PRODUCT_TYPE_NEW,
          :PRODUCT_TYPE_RENEW
        ))
      WITH SYSTEM_MODE
    ];
  }

  public static EstimateCreateController.ProductDefaultDto getProductDefaults(
    Id productId
  ) {
    if (productId == null) {
      return null;
    }

    Set<String> selectFields = new Set<String>{
      'Id',
      'Name',
      'UnitName__c',
      'UnitPrice__c',
      'invoicetype__c',
      'BillingType__c',
      'RevenueRecognitionBasis__c',
      'AvailableForContract__c'
    };
    selectFields.addAll(
      ContractWizardFieldService.getReferencedProduct2FieldApiNames()
    );

    String soql =
      'SELECT ' +
      String.join(new List<String>(selectFields), ',') +
      ' FROM Product2' +
      ' WHERE Id = :productId' +
      ' WITH SYSTEM_MODE' +
      ' LIMIT 1';
    List<Product2> products = Database.query(soql);

    if (products.isEmpty()) {
      return null;
    }

    Product2 product = products[0];
    if (product.AvailableForContract__c != true) {
      throw EstimateValidationService.estS3NewException(
        '026',
        '契約管理で利用可能な商品のみ選択できます。'
      );
    }
    EstimateCreateController.ProductDefaultDto dto = new EstimateCreateController.ProductDefaultDto();
    dto.productName = product.Name;
    dto.unitName = product.UnitName__c;
    dto.unitPrice = product.UnitPrice__c;
    dto.invoiceType = ContractMetadataService.resolveInvoiceSettingForBillingType(
      product.BillingType__c,
      product.invoicetype__c
    );
    dto.billingType = product.BillingType__c;
    try {
      dto.revenueRecognitionBasis = ContractMetadataService.resolveRevenueRecognitionBasis(
        product.RevenueRecognitionBasis__c
      );
    } catch (ContractMetadataService.RevenueRecognitionBasisException ex) {
      throw EstimateValidationService.wrapAura(ex.getMessage());
    }
    dto.billingCycle = EstimateCreateSupport.resolveRecurringBillingCycleLabel(
      product.BillingType__c
    );
    dto.displayUnit = EstimateCreateSupport.buildDisplayUnit(
      product.UnitName__c,
      product.BillingType__c
    );
    dto.productVisibilityContext = ContractWizardFieldService.buildProductVisibilityContext(
      product
    );
    return dto;
  }

  public static List<ContractMetadataService.InvoiceSettingOption> getInvoiceSettingOptions() {
    return ContractMetadataService.getActiveInvoiceSettingOptions();
  }

  public static String getDefaultInvoiceSettingLabel() {
    String label = ContractMetadataService.getDefaultInvoiceSettingLabel();
    return label == null ? '' : label;
  }

  public static List<EstimateCreateController.BillingAccountOptionDto> getBillingAccountsByAccount(
    Id accountId
  ) {
    List<EstimateCreateController.BillingAccountOptionDto> options = new List<EstimateCreateController.BillingAccountOptionDto>();
    if (accountId == null) {
      return options;
    }

    for (BillingAccount__c billingAccount : [
      SELECT Id, Name
      FROM BillingAccount__c
      WHERE Account__c = :accountId
      WITH SYSTEM_MODE
      ORDER BY Name
      LIMIT 200
    ]) {
      EstimateCreateController.BillingAccountOptionDto option = new EstimateCreateController.BillingAccountOptionDto();
      option.id = billingAccount.Id;
      option.name = billingAccount.Name;
      options.add(option);
    }
    return options;
  }

  public static List<EstimateCreateController.ContractServiceOptionDto> getActiveContractServicesByAccount(
    Id accountId
  ) {
    List<EstimateCreateController.ContractServiceOptionDto> options = new List<EstimateCreateController.ContractServiceOptionDto>();
    if (accountId == null) {
      return options;
    }

    // 契約サービスを直クエリせず、受注済の契約履歴からサービスを洗い出す。
    // サービスごとの最新受注済（Version 最大）が New/Change/Renew なら未解約扱い。
    Map<Id, ContractHistory__c> latestOrderedByServiceId = new Map<Id, ContractHistory__c>();
    for (ContractHistory__c history : [
      SELECT
        ContractService__c,
        ContractService__r.Name,
        ContractService__r.Lifecycle__c,
        ContractService__r.Status__c,
        ContractService__r.RenewalRemainingMonths__c,
        Name,
        Version__c,
        Type__c,
        CurrentTermStartDate__c,
        CurrentTermEndDate__c,
        ContractService__r.BiilingAcccount__c,
        ContractService__r.BiilingAcccount__r.Name,
        ContractService__r.TaxPercent__c
      FROM ContractHistory__c
      WHERE
        ContractService__r.Account__c = :accountId
        AND historystatus__c = :HISTORY_STATUS_ORDERED
        AND ContractService__c != NULL
      WITH SYSTEM_MODE
      ORDER BY ContractService__c, Version__c DESC NULLS LAST
      LIMIT 10000
    ]) {
      if (latestOrderedByServiceId.containsKey(history.ContractService__c)) {
        continue;
      }
      latestOrderedByServiceId.put(history.ContractService__c, history);
    }

    List<String> sortKeys = new List<String>();
    Map<String, EstimateCreateController.ContractServiceOptionDto> optionBySortKey = new Map<String, EstimateCreateController.ContractServiceOptionDto>();
    Map<Id, EstimateCreateController.ContractServiceOptionDto> termOptionByHistoryId = new Map<Id, EstimateCreateController.ContractServiceOptionDto>();
    Map<Id, Date> termStartByHistoryId = new Map<Id, Date>();
    Map<Id, Date> termEndByHistoryId = new Map<Id, Date>();
    for (Id serviceId : latestOrderedByServiceId.keySet()) {
      ContractHistory__c history = latestOrderedByServiceId.get(serviceId);
      String historyType = history.Type__c;
      if (
        historyType != HISTORY_TYPE_NEW &&
        historyType != HISTORY_TYPE_CHANGE &&
        historyType != HISTORY_TYPE_RENEW &&
        historyType != LEGACY_HISTORY_TYPE_ADD
      ) {
        continue;
      }

      EstimateCreateController.ContractServiceOptionDto option = new EstimateCreateController.ContractServiceOptionDto();
      option.id = serviceId;
      option.name = history.ContractService__r.Name;
      option.lifecycle = history.ContractService__r.Lifecycle__c;
      if (String.isBlank(option.lifecycle)) {
        continue;
      }
      option.lifecycleLabel = toLifecycleLabel(option.lifecycle);
      option.status = history.ContractService__r.Status__c;
      option.statusLabel = option.status == null ? '' : option.status;
      if (option.lifecycle == ContractDomainConstants.LIFECYCLE_TERM) {
        option.termStart = history.CurrentTermStartDate__c;
        option.termEnd = history.CurrentTermEndDate__c;
        option.renewalRemainingMonths = history.ContractService__r.RenewalRemainingMonths__c;
        if (
          history.Id != null &&
          option.termStart != null &&
          option.termEnd != null
        ) {
          termOptionByHistoryId.put(history.Id, option);
          termStartByHistoryId.put(history.Id, option.termStart);
          termEndByHistoryId.put(history.Id, option.termEnd);
        }
      }
      option.historyName = history.Name;
      option.version = history.Version__c;
      option.billingAccountId = history.ContractService__r.BiilingAcccount__c;
      option.billingAccountName = history.ContractService__r.BiilingAcccount__r !=
        null
        ? history.ContractService__r.BiilingAcccount__r.Name
        : null;
      option.taxPercent = TaxCalculationUtil.fromPercentFieldStorage(
        history.ContractService__r.TaxPercent__c
      );

      String sortKey =
        (option.name == null ? '' : option.name) +
        '|' +
        String.valueOf(serviceId);
      sortKeys.add(sortKey);
      optionBySortKey.put(sortKey, option);
    }

    fillCurrentProductNamesForTermOptions(
      termOptionByHistoryId,
      termStartByHistoryId,
      termEndByHistoryId
    );

    sortKeys.sort();
    Integer limitCount = Math.min(sortKeys.size(), 200);
    for (Integer i = 0; i < limitCount; i++) {
      options.add(optionBySortKey.get(sortKeys[i]));
    }
    return options;
  }

  /**
   * 期間契約の最新受注履歴について、現契約期間と日付が重なる継続課金商品名を
   * 重複なくカンマ区切りで option.currentProductNames に載せる。
   */
  private static void fillCurrentProductNamesForTermOptions(
    Map<Id, EstimateCreateController.ContractServiceOptionDto> termOptionByHistoryId,
    Map<Id, Date> termStartByHistoryId,
    Map<Id, Date> termEndByHistoryId
  ) {
    if (termOptionByHistoryId == null || termOptionByHistoryId.isEmpty()) {
      return;
    }

    Set<Id> historyIds = termOptionByHistoryId.keySet();
    Map<Id, List<String>> namesByHistoryId = new Map<Id, List<String>>();
    Map<Id, Set<String>> seenByHistoryId = new Map<Id, Set<String>>();

    for (ContractProduct__c product : [
      SELECT ContractHistory__c, Product__r.Name, StartDate__c, Enddate__c
      FROM ContractProduct__c
      WHERE
        ContractHistory__c IN :historyIds
        AND BillingType__c = :BILLING_TYPE_RECURRING
        AND Quantity__c > 0
        AND (
          Type__c = NULL
          OR Type__c IN (
            :PRODUCT_TYPE_REMAKE,
            :PRODUCT_TYPE_NEW,
            :PRODUCT_TYPE_RENEW
          )
        )
      WITH SYSTEM_MODE
      ORDER BY Product__r.Name ASC
    ]) {
      Id historyId = product.ContractHistory__c;
      Date termStart = termStartByHistoryId.get(historyId);
      Date termEnd = termEndByHistoryId.get(historyId);
      if (termStart == null || termEnd == null) {
        continue;
      }
      Date productStart = product.StartDate__c;
      Date productEnd = product.Enddate__c;
      if (productStart == null || productEnd == null) {
        continue;
      }
      // 現契約期間と重なる明細だけ
      if (productStart > termEnd || productEnd < termStart) {
        continue;
      }
      String productName = product.Product__r != null
        ? product.Product__r.Name
        : null;
      if (String.isBlank(productName)) {
        continue;
      }
      if (!seenByHistoryId.containsKey(historyId)) {
        seenByHistoryId.put(historyId, new Set<String>());
        namesByHistoryId.put(historyId, new List<String>());
      }
      if (seenByHistoryId.get(historyId).contains(productName)) {
        continue;
      }
      seenByHistoryId.get(historyId).add(productName);
      namesByHistoryId.get(historyId).add(productName);
    }

    for (Id historyId : namesByHistoryId.keySet()) {
      EstimateCreateController.ContractServiceOptionDto option = termOptionByHistoryId.get(
        historyId
      );
      if (option == null) {
        continue;
      }
      option.currentProductNames = String.join(
        namesByHistoryId.get(historyId),
        ','
      );
    }
  }

  /** 仕様: Core 第5.2節。宛名・To/Cc/Bcc・支払条件・請求日ルールの最新。 */
  public static EstimateCreateController.BillingAccountInvoiceSettingsDto getBillingAccountInvoiceSettings(
    Id billingAccountId
  ) {
    EstimateCreateController.BillingAccountInvoiceSettingsDto dto = new EstimateCreateController.BillingAccountInvoiceSettingsDto();
    dto.billingCustomFields = new Map<String, Object>();
    if (billingAccountId == null) {
      return dto;
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
      WHERE Id = :billingAccountId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (billingAccounts.isEmpty()) {
      return dto;
    }
    BillingAccount__c loaded = billingAccounts[0];
    dto.billingCustomFields.put('BillingAddressee__c', loaded.BillingAddressee__c);
    dto.billingCustomFields.put('BillingEmailTo__c', loaded.BillingEmailTo__c);
    dto.billingCustomFields.put('BillingEmailCc__c', loaded.BillingEmailCc__c);
    dto.billingCustomFields.put('BillingEmailBcc__c', loaded.BillingEmailBcc__c);
    for (String fieldApiName : BillingScheduleService.BILLING_ACCOUNT_SCHEDULE_FIELDS) {
      dto.billingCustomFields.put(fieldApiName, loaded.get(fieldApiName));
    }
    return dto;
  }

  public static String getEstimateRemarkMasterText(Id masterId) {
    if (masterId == null) {
      return '';
    }

    List<EstimateNoteMaster__c> masters = [
      SELECT NoteText__c
      FROM EstimateNoteMaster__c
      WHERE Id = :masterId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (masters.isEmpty()) {
      return '';
    }
    return masters[0].NoteText__c == null ? '' : masters[0].NoteText__c;
  }

  private static String toLifecycleLabel(String lifecycle) {
    if (lifecycle == ContractDomainConstants.LIFECYCLE_TERM) {
      return '期間契約';
    }
    if (lifecycle == ContractDomainConstants.LIFECYCLE_SPOT) {
      return '都度契約';
    }
    return '';
  }

}
