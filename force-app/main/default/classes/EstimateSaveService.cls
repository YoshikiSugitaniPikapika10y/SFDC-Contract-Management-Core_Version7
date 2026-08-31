/**
 * Estimate persistence (create/update/replace products).
 */
public without sharing class EstimateSaveService {
  private static final String HISTORY_STATUS_ESTIMATE = ContractDomainConstants.HISTORY_STATUS_ESTIMATE;
  private static final String HISTORY_STATUS_ARCHIVE = ContractDomainConstants.HISTORY_STATUS_ARCHIVE;
  private static final String HISTORY_STATUS_ORDERED = ContractDomainConstants.HISTORY_STATUS_ORDERED;
  private static final String HISTORY_TYPE_NEW = ContractDomainConstants.HISTORY_TYPE_NEW;
  private static final String HISTORY_TYPE_CHANGE = ContractDomainConstants.HISTORY_TYPE_CHANGE;
  private static final String HISTORY_TYPE_RENEW = ContractDomainConstants.HISTORY_TYPE_RENEW;
  private static final String HISTORY_TYPE_CANCEL = ContractDomainConstants.HISTORY_TYPE_CANCEL;
  private static final String BILLING_TYPE_RECURRING = ContractDomainConstants.BILLING_TYPE_RECURRING;
  private static final String BILLING_TYPE_ONE_TIME = ContractDomainConstants.BILLING_TYPE_ONE_TIME;
  private static final String MONTHLY_BILLING_CYCLE = ContractDomainConstants.MONTHLY_BILLING_CYCLE;
  private static final String PRODUCT_TYPE_ORIGINAL = ContractDomainConstants.PRODUCT_TYPE_ORIGINAL;
  private static final String PRODUCT_TYPE_REMAKE = ContractDomainConstants.PRODUCT_TYPE_REMAKE;
  private static final String LEGACY_PRODUCT_TYPE_DERIVATIVE = ContractDomainConstants.LEGACY_PRODUCT_TYPE_DERIVATIVE;
  private static final String PRODUCT_TYPE_NEW = ContractDomainConstants.PRODUCT_TYPE_NEW;
  private static final String PRODUCT_TYPE_RENEW = ContractDomainConstants.PRODUCT_TYPE_RENEW;
  private static final Integer NOTE_MAX_LENGTH = ContractDomainConstants.NOTE_MAX_LENGTH;

  public static EstimateCreateController.EstimateSaveResult saveEstimate(
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
      null,
      null,
      null
    );
  }

  public static EstimateCreateController.EstimateSaveResult saveEstimate(
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
      null,
      null
    );
  }

  public static EstimateCreateController.EstimateSaveResult saveEstimate(
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
      editHistoryId == null
        ? null
        : ContractOptimisticLockUtil.toHistoryProductToken(editHistoryId)
    );
  }

  public static EstimateCreateController.EstimateSaveResult saveEstimate(
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
      // 仕様: Core 第1.1.10節、第4.6節。税率未指定は埋めない。初期値10%は画面入力。
      null,
      null,
      null,
      null
    );
  }

  public static EstimateCreateController.EstimateSaveResult saveEstimate(
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

  /** 仕様: Core 第4.3.12節 */
  public static EstimateCreateController.EstimateSaveResult saveEstimate(
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
    EstimateCreateController.EstimateSaveRequest request = new EstimateCreateController.EstimateSaveRequest();
    request.opportunityId = opportunityId;
    request.selectedType = selectedType;
    request.contractServiceName = contractServiceName;
    request.contractServiceId = contractServiceId;
    request.previousHistoryId = previousHistoryId;
    request.contractStartDate = contractStartDate;
    request.contractEndDate = contractEndDate;
    request.effectiveDate = effectiveDate;
    request.applicationDate = applicationDate;
    request.products = EstimateCreateSupport.parseProducts(productsJson);
    request.estimateRemarkMasterId = estimateRemarkMasterId;
    request.remarksText = remarksText;
    request.billingAccountId = billingAccountId;
    request.copyFromHistoryId = copyFromHistoryId;
    request.editHistoryId = editHistoryId;
    request.expectedLastModifiedToken = expectedLastModifiedToken;
    request.contractServiceCustomFields = ContractWizardFieldService.parseCustomFieldsJson(
      contractServiceCustomFieldsJson
    );
    request.contractHistoryCustomFields = ContractWizardFieldService.parseCustomFieldsJson(
      contractHistoryCustomFieldsJson
    );
    request.contractHistoryName = contractHistoryName;
    // 仕様: Core 第1.1.10節、第4.6節。Newの税率nullは10で埋めない。初期値10%は画面入力。
    request.taxPercent = taxPercent;
    request.estimateDate = estimateDate;
    request.estimateValidDate = estimateValidDate;
    request.estimateSendContactId = estimateSendContactId;
    request.businessOperationKey = AccountingCauseLockService.resolveOrIssueOperationKey(
      businessOperationKey
    );

    if (
      request.opportunityId == null &&
      request.selectedType == null &&
      request.products == null
    ) {
      throw EstimateValidationService.estSaveException(
        '001',
        '保存データがありません。'
      );
    }

    if (String.isBlank(request.selectedType)) {
      throw EstimateValidationService.estS1Exception(
        '001',
        'タイプを選択してください。'
      );
    }

    if (request.editHistoryId != null) {
      return writeEstimateLog(
        request,
        saveEditedEstimate(request, contractHistoryName)
      );
    }

    EstimateCreateController.EstimateSaveResult existingByKey = findExistingByOperationKey(
      request.businessOperationKey
    );
    if (existingByKey != null) {
      return writeEstimateLog(request, existingByKey);
    }

    EstimateValidationService.validateWizardCustomFields(request, false);

    if (request.selectedType == 'New') {
      EstimateValidationService.validateNewSaveRequest(
        request,
        contractHistoryName
      );
      return writeEstimateLog(
        request,
        saveNewEstimate(request, contractHistoryName)
      );
    }

    if (request.selectedType == 'Change') {
      EstimateValidationService.validateChangeSaveRequest(
        request,
        contractHistoryName
      );
      return writeEstimateLog(
        request,
        saveChangeEstimate(request, contractHistoryName)
      );
    }

    if (request.selectedType == 'Renew') {
      EstimateValidationService.validateRenewSaveRequest(
        request,
        contractHistoryName
      );
      return writeEstimateLog(
        request,
        saveChangeEstimate(request, contractHistoryName)
      );
    }

    if (request.selectedType == 'Cancel') {
      EstimateValidationService.validateCancelSaveRequest(
        request,
        contractHistoryName
      );
      return writeEstimateLog(
        request,
        saveCancelEstimate(request, contractHistoryName)
      );
    }

    throw EstimateValidationService.estSaveException(
      '002',
      'New、Change、Renew、Cancelタイプのみ保存できます。'
    );
  }

  /** 仕様: Core 第4.3.12節 */
  public static EstimateCreateController.EstimateSaveResult saveEditedEstimate(
    EstimateCreateController.EstimateSaveRequest request,
    String contractHistoryName
  ) {
    if (request != null) {
      request.businessOperationKey = AccountingCauseLockService.resolveOrIssueOperationKey(
        request.businessOperationKey
      );
    }
    ContractHistory__c existing = loadEditableEstimateHistory(
      request.editHistoryId
    );
    if (existing.BusinessOperationKey__c == request.businessOperationKey) {
      return buildSaveResult(
        existing.ContractService__c,
        existing.Id,
        existing.Id
      );
    }
    ContractOptimisticLockUtil.assertRequiredHistoryProductsUnchanged(
      existing.Id,
      request.expectedLastModifiedToken
    );
    if (existing.Opportunity__c != request.opportunityId) {
      throw EstimateValidationService.wrapAura(
        '編集対象の見積と商談が一致しません。'
      );
    }
    if (
      String.isNotBlank(request.selectedType) &&
      existing.Type__c != request.selectedType
    ) {
      throw EstimateValidationService.wrapAura(
        '見積編集ではタイプを変更できません。'
      );
    }

    request.selectedType = existing.Type__c;
    // Edit では PreviousHistory をクライアントから書き換えさせない（DB 値を正とする）
    if (
      existing.Type__c == 'Change' ||
      existing.Type__c == 'Renew' ||
      existing.Type__c == 'Cancel'
    ) {
      request.previousHistoryId = existing.PreviousHistory__c;
      request.contractServiceId = existing.ContractService__c;
    }
    Boolean orderedCustomFieldsOnly =
      existing.historystatus__c == HISTORY_STATUS_ORDERED;
    EstimateValidationService.validateWizardCustomFields(
      request,
      orderedCustomFieldsOnly
    );

    if (orderedCustomFieldsOnly) {
      return updateOrderedEstimateCustomFieldsOnly(existing, request);
    }

    if (request.selectedType == 'New') {
      EstimateValidationService.validateNewSaveRequest(
        request,
        contractHistoryName
      );
      return updateNewEstimate(existing, request, contractHistoryName);
    }
    if (request.selectedType == 'Change') {
      EstimateValidationService.validateChangeSaveRequest(
        request,
        contractHistoryName
      );
      return updateChangeEstimate(existing, request, contractHistoryName);
    }
    if (request.selectedType == 'Renew') {
      EstimateValidationService.validateRenewSaveRequest(
        request,
        contractHistoryName
      );
      return updateChangeEstimate(existing, request, contractHistoryName);
    }
    if (request.selectedType == 'Cancel') {
      EstimateValidationService.validateCancelSaveRequest(
        request,
        contractHistoryName
      );
      return updateCancelEstimate(existing, request, contractHistoryName);
    }
    throw EstimateValidationService.estSaveException(
      '002',
      'New、Change、Renew、Cancelタイプのみ保存できます。'
    );
  }

  public static ContractHistory__c loadEditableEstimateHistory(
    Id editHistoryId
  ) {
    if (editHistoryId == null) {
      throw EstimateValidationService.wrapAura(
        '編集対象の契約履歴が見つかりません。'
      );
    }
    List<ContractHistory__c> histories = [
      SELECT
        Id,
        Name,
        Type__c,
        Version__c,
        historystatus__c,
        Opportunity__c,
        ContractService__c,
        PreviousHistory__c,
        LastModifiedDate,
        BusinessOperationKey__c
      FROM ContractHistory__c
      WHERE Id = :editHistoryId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    if (histories.isEmpty()) {
      throw EstimateValidationService.wrapAura(
        '編集対象の契約履歴が見つかりません。'
      );
    }
    ContractHistory__c history = histories[0];
    if (
      history.historystatus__c != HISTORY_STATUS_ESTIMATE &&
      history.historystatus__c != HISTORY_STATUS_ORDERED
    ) {
      throw EstimateValidationService.wrapAura(
        'Estimate / Ordered 状態の契約履歴のみ編集できます。'
      );
    }
    return history;
  }

  /** 仕様: Core 第4.3節、第4.3.1節、第11.4.3節。Ordered編集は見積追加項目と受注追加項目だけを保存する。 */
  public static EstimateCreateController.EstimateSaveResult updateOrderedEstimateCustomFieldsOnly(
    ContractHistory__c existing,
    EstimateCreateController.EstimateSaveRequest request
  ) {
    Id serviceId = existing.ContractService__c;
    if (serviceId == null) {
      throw EstimateValidationService.wrapAura(
        '契約サービスが見つかりません。'
      );
    }

    ContractHistory__c historyUpdate = new ContractHistory__c(Id = existing.Id);
    historyUpdate.Type__c = existing.Type__c;
    applyOperationKey(historyUpdate, request);
    applyContractHistoryCustomFields(historyUpdate, request);
    try {
      String requiredError = OrderWizardFieldService.validateRequiredHistoryFields(
        request.contractHistoryCustomFields,
        existing.Type__c
      );
      if (String.isNotBlank(requiredError)) {
        throw EstimateValidationService.wrapAura(requiredError);
      }
      OrderWizardFieldService.applyHistoryFields(
        historyUpdate,
        request.contractHistoryCustomFields
      );
    } catch (OrderWizardFieldService.WizardFieldConfigException ex) {
      throw EstimateValidationService.wrapAura(ex.getMessage());
    }
    SystemContextAccess.updateRecords(new List<SObject>{ historyUpdate });

    updateOrderedProductCustomFieldsOnly(existing.Id, request);

    return buildSaveResult(serviceId, existing.Id, existing.Id);
  }

  public static void updateOrderedProductCustomFieldsOnly(
    Id contractHistoryId,
    EstimateCreateController.EstimateSaveRequest request
  ) {
    if (
      contractHistoryId == null ||
      request == null ||
      request.products == null ||
      request.products.isEmpty() ||
      request.selectedType == 'Cancel'
    ) {
      return;
    }

    Map<Id, EstimateCreateController.ProductLineItem> lineByProductId = new Map<Id, EstimateCreateController.ProductLineItem>();
    for (EstimateCreateController.ProductLineItem line : request.products) {
      if (line == null || line.productId == null) {
        continue;
      }
      if (line.contractProductId == null) {
        throw EstimateValidationService.wrapAura(
          'Ordered編集では見積商品IDが必要です。画面を開き直して再度保存してください。'
        );
      }
      lineByProductId.put(line.contractProductId, line);
    }
    if (lineByProductId.isEmpty()) {
      return;
    }

    Set<Id> productIds = lineByProductId.keySet();
    List<ContractProduct__c> existingProducts = [
      SELECT Id, Product__c
      FROM ContractProduct__c
      WHERE ContractHistory__c = :contractHistoryId AND Id IN :productIds
      WITH SYSTEM_MODE
    ];
    if (existingProducts.size() != productIds.size()) {
      throw EstimateValidationService.wrapAura(
        'Ordered編集の対象見積商品が一致しません。'
      );
    }

    // 画面の visibility context が空でも、新規作成保存と同様に Product2 から再構築する
    Map<Id, Product2> productById = loadProductBillingTypes(request.products);

    List<ContractProduct__c> toUpdate = new List<ContractProduct__c>();
    for (ContractProduct__c existingProduct : existingProducts) {
      EstimateCreateController.ProductLineItem line = lineByProductId.get(
        existingProduct.Id
      );
      if (line == null) {
        continue;
      }
      ContractProduct__c productUpdate = new ContractProduct__c(
        Id = existingProduct.Id
      );
      if (EstimateCreateSupport.isChangeOriginalLine(line)) {
        ContractWizardFieldService.applyCustomFields(
          productUpdate,
          ContractWizardFieldService.buildClearedCustomFields(
            ContractWizardFieldService.WizardTarget.ContractProduct
          ),
          ContractWizardFieldService.WizardTarget.ContractProduct
        );
      } else {
        // Ordered編集でも Type 非表示は書き込まず、Product2 非表示は null クリアする。
        // Visibility 判定は常に Product2 から再構築（クライアント context は信じない）。
        Id catalogProductId = line.productId != null
          ? line.productId
          : existingProduct.Product__c;
        Map<String, String> visibilityContext = ContractWizardFieldService.buildProductVisibilityContext(
          productById.get(catalogProductId)
        );
        ContractWizardFieldService.applyCustomFields(
          productUpdate,
          ContractWizardFieldService.filterCustomFieldsByVisibility(
            line.customFields,
            ContractWizardFieldService.WizardTarget.ContractProduct,
            visibilityContext,
            request.selectedType
          ),
          ContractWizardFieldService.WizardTarget.ContractProduct
        );
      }
      toUpdate.add(productUpdate);
    }
    if (!toUpdate.isEmpty()) {
      SystemContextAccess.updateRecords(toUpdate);
    }
  }

  public static EstimateCreateController.EstimateSaveResult updateNewEstimate(
    ContractHistory__c existing,
    EstimateCreateController.EstimateSaveRequest request,
    String contractHistoryName
  ) {
    Opportunity opportunity = [
      SELECT Id, AccountId
      FROM Opportunity
      WHERE Id = :request.opportunityId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (opportunity.AccountId == null) {
      throw EstimateValidationService.estSaveNewException(
        '001',
        '商談に取引先が設定されていません。'
      );
    }

    Id serviceId = existing.ContractService__c;
    if (serviceId == null) {
      throw EstimateValidationService.wrapAura(
        '契約サービスが見つかりません。'
      );
    }

    ContractService__c contractService = new ContractService__c(
      Id = serviceId,
      Name = request.contractServiceName,
      BiilingAcccount__c = request.billingAccountId,
      TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(
        request.taxPercent
      )
    );
    applyContractServiceCustomFields(contractService, request);
    Boolean previousWrite = ContractServiceWriteGuard.isPackageWriteAllowed();
    ContractServiceWriteGuard.allowPackageWrite(true);
    try {
      SystemContextAccess.updateRecords(new List<SObject>{ contractService });
    } finally {
      ContractServiceWriteGuard.allowPackageWrite(previousWrite);
    }

    Date serviceStartDate = EstimateCreateSupport.parseDate(
      request.contractStartDate
    );
    Date serviceEndDate = EstimateCreateSupport.parseDate(
      request.contractEndDate
    );
    existing.Name = contractHistoryName;
    existing.CurrentTermStartDate__c = serviceStartDate;
    existing.CurrentTermEndDate__c = serviceEndDate;
    existing.EffectiveDate__c = EstimateCreateSupport.parseDate(
      request.effectiveDate
    );
    applyEstimateDocumentIfEnabled(existing, request);
    applyEstimateSendContact(existing, request);
    applyContractHistoryCustomFields(existing, request);
    applyOperationKey(existing, request);
    SystemContextAccess.updateRecords(new List<SObject>{ existing });

    replaceEstimateProducts(existing.Id, opportunity.AccountId, request);

    return buildSaveResult(serviceId, existing.Id, existing.Id);
  }

  /** 仕様: Core 第3.4.2節、第4.9節 */
  public static EstimateCreateController.EstimateSaveResult updateChangeEstimate(
    ContractHistory__c existing,
    EstimateCreateController.EstimateSaveRequest request,
    String contractHistoryName
  ) {
    Id serviceId = existing.ContractService__c;
    if (serviceId == null) {
      throw EstimateValidationService.wrapAura(
        '契約サービスが見つかりません。'
      );
    }
    List<ContractService__c> services = [
      SELECT Id, Account__c
      FROM ContractService__c
      WHERE Id = :serviceId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (services.isEmpty()) {
      throw EstimateValidationService.wrapAura(
        '契約サービスが見つかりません。'
      );
    }

    Date serviceStartDate = EstimateCreateSupport.parseDate(
      request.contractStartDate
    );
    Date serviceEndDate = EstimateCreateSupport.parseDate(
      request.contractEndDate
    );
    existing.Name = contractHistoryName;
    existing.CurrentTermStartDate__c = serviceStartDate;
    existing.CurrentTermEndDate__c = serviceEndDate;
    existing.EffectiveDate__c = EstimateCreateSupport.parseDate(
      request.effectiveDate
    );
    applyEstimateDocumentIfEnabled(existing, request);
    applyEstimateSendContact(existing, request);
    applyContractHistoryCustomFields(existing, request);
    applyOperationKey(existing, request);
    SystemContextAccess.updateRecords(new List<SObject>{ existing });

    if (request.selectedType == 'Change') {
      request.products = EstimateValidationService.normalizeChangeProductsForSave(
        request.products
      );
    }

    replaceEstimateProducts(existing.Id, services[0].Account__c, request);

    return buildSaveResult(serviceId, existing.Id, existing.Id);
  }

  public static EstimateCreateController.EstimateSaveResult updateCancelEstimate(
    ContractHistory__c existing,
    EstimateCreateController.EstimateSaveRequest request,
    String contractHistoryName
  ) {
    Id serviceId = existing.ContractService__c;
    Date cancelDate = EstimateCreateSupport.parseDate(
      request.contractStartDate
    );
    if (cancelDate == null) {
      cancelDate = EstimateCreateSupport.parseDate(request.contractEndDate);
    }

    existing.Name = contractHistoryName;
    existing.CurrentTermStartDate__c = cancelDate;
    existing.CurrentTermEndDate__c = cancelDate;
    existing.EffectiveDate__c = EstimateCreateSupport.parseDate(
      request.effectiveDate
    );
    applyEstimateDocumentIfEnabled(existing, request);
    applyEstimateSendContact(existing, request);
    applyContractHistoryCustomFields(existing, request);
    applyOperationKey(existing, request);
    SystemContextAccess.updateRecords(new List<SObject>{ existing });

    replaceEstimateProducts(existing.Id, null, request);

    return buildSaveResult(
      existing.ContractService__c,
      existing.Id,
      existing.Id
    );
  }

  public static void replaceEstimateProducts(
    Id contractHistoryId,
    Id accountId,
    EstimateCreateController.EstimateSaveRequest request
  ) {
    List<ContractProduct__c> existingProducts = [
      SELECT Id
      FROM ContractProduct__c
      WHERE ContractHistory__c = :contractHistoryId
      WITH SYSTEM_MODE
    ];
    if (!existingProducts.isEmpty()) {
      SystemContextAccess.deleteRecords(existingProducts);
    }

    if (request.selectedType == 'Cancel') {
      return;
    }

    SystemContextAccess.insertRecords(
      buildContractProducts(contractHistoryId, accountId, request)
    );
  }

  /** 仕様: Core 第3.4.2節、第4.9節 */
  public static EstimateCreateController.EstimateSaveResult saveNewEstimate(
    EstimateCreateController.EstimateSaveRequest request,
    String contractHistoryName
  ) {
    // 仕様: Core 第11.4.2節
    FieldCopyDefinitionService.validateAllDefinitions();
    Opportunity opportunity = [
      SELECT Id, AccountId
      FROM Opportunity
      WHERE Id = :request.opportunityId
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    if (opportunity.AccountId == null) {
      throw EstimateValidationService.estSaveNewException(
        '001',
        '商談に取引先が設定されていません。'
      );
    }

    Date serviceStartDate = EstimateCreateSupport.parseDate(
      request.contractStartDate
    );
    Date serviceEndDate = EstimateCreateSupport.parseDate(
      request.contractEndDate
    );

    ContractService__c contractService = new ContractService__c(
      Name = request.contractServiceName,
      Account__c = opportunity.AccountId,
      BiilingAcccount__c = request.billingAccountId,
      TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(
        request.taxPercent
      )
    );
    applyContractServiceCustomFields(contractService, request);
    Boolean previousWrite = ContractServiceWriteGuard.isPackageWriteAllowed();
    ContractServiceWriteGuard.allowPackageWrite(true);
    try {
      SystemContextAccess.insertRecords(new List<SObject>{ contractService });
    } finally {
      ContractServiceWriteGuard.allowPackageWrite(previousWrite);
    }

    ContractHistory__c contractHistory = new ContractHistory__c(
      Name = contractHistoryName,
      ContractService__c = contractService.Id,
      Type__c = request.selectedType,
      historystatus__c = HISTORY_STATUS_ESTIMATE,
      Version__c = 1,
      CurrentTermStartDate__c = serviceStartDate,
      CurrentTermEndDate__c = serviceEndDate,
      EffectiveDate__c = EstimateCreateSupport.parseDate(request.effectiveDate),
      Opportunity__c = opportunity.Id
    );
    applyEstimateDocumentIfEnabled(contractHistory, request);
    applyEstimateSendContact(contractHistory, request);
    applyContractHistoryCustomFields(contractHistory, request);
    applyNotAutoRenewFieldCopy(contractHistory, request);
    applyOperationKey(contractHistory, request);
    SystemContextAccess.insertRecords(new List<SObject>{ contractHistory });

    SystemContextAccess.insertRecords(
      buildContractProducts(contractHistory.Id, opportunity.AccountId, request)
    );

    return buildSaveResult(
      contractService.Id,
      contractHistory.Id,
      contractHistory.Id
    );
  }

  public static EstimateCreateController.EstimateSaveResult saveChangeEstimate(
    EstimateCreateController.EstimateSaveRequest request,
    String contractHistoryName
  ) {
    // 仕様: Core 第11.4.2節
    FieldCopyDefinitionService.validateAllDefinitions();
    Opportunity opportunity = [
      SELECT Id
      FROM Opportunity
      WHERE Id = :request.opportunityId
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    List<ContractService__c> services = [
      SELECT Id, Account__c
      FROM ContractService__c
      WHERE Id = :request.contractServiceId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (services.isEmpty()) {
      throw EstimateValidationService.wrapAura(
        '契約サービスが見つかりません。'
      );
    }

    Date serviceStartDate = EstimateCreateSupport.parseDate(
      request.contractStartDate
    );
    Date serviceEndDate = EstimateCreateSupport.parseDate(
      request.contractEndDate
    );

    ContractHistory__c contractHistory = new ContractHistory__c(
      Name = contractHistoryName,
      ContractService__c = request.contractServiceId,
      Type__c = request.selectedType,
      historystatus__c = HISTORY_STATUS_ESTIMATE,
      Version__c = resolveEstimateHistoryVersion(
        request.contractServiceId,
        request.copyFromHistoryId
      ),
      CurrentTermStartDate__c = serviceStartDate,
      CurrentTermEndDate__c = serviceEndDate,
      EffectiveDate__c = EstimateCreateSupport.parseDate(request.effectiveDate),
      Opportunity__c = opportunity.Id,
      PreviousHistory__c = request.previousHistoryId
    );
    applyEstimateDocumentIfEnabled(contractHistory, request);
    applyEstimateSendContact(contractHistory, request);
    applyContractHistoryCustomFields(contractHistory, request);
    applyNotAutoRenewFieldCopy(contractHistory, request);
    applyOperationKey(contractHistory, request);
    SystemContextAccess.insertRecords(new List<SObject>{ contractHistory });

    if (request.selectedType == 'Change') {
      request.products = EstimateValidationService.normalizeChangeProductsForSave(
        request.products
      );
    }

    SystemContextAccess.insertRecords(
      buildContractProducts(contractHistory.Id, services[0].Account__c, request)
    );

    return buildSaveResult(
      request.contractServiceId,
      contractHistory.Id,
      contractHistory.Id
    );
  }

  public static EstimateCreateController.EstimateSaveResult saveCancelEstimate(
    EstimateCreateController.EstimateSaveRequest request,
    String contractHistoryName
  ) {
    // 仕様: Core 第11.4.2節
    FieldCopyDefinitionService.validateAllDefinitions();
    Opportunity opportunity = [
      SELECT Id
      FROM Opportunity
      WHERE Id = :request.opportunityId
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    List<ContractService__c> services = [
      SELECT Id
      FROM ContractService__c
      WHERE Id = :request.contractServiceId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (services.isEmpty()) {
      throw EstimateValidationService.wrapAura(
        '契約サービスが見つかりません。'
      );
    }

    Date cancelDate = EstimateCreateSupport.parseDate(
      request.contractStartDate
    );
    if (cancelDate == null) {
      cancelDate = EstimateCreateSupport.parseDate(request.contractEndDate);
    }

    ContractHistory__c contractHistory = new ContractHistory__c(
      Name = contractHistoryName,
      ContractService__c = request.contractServiceId,
      Type__c = request.selectedType,
      historystatus__c = HISTORY_STATUS_ESTIMATE,
      Version__c = resolveEstimateHistoryVersion(
        request.contractServiceId,
        request.copyFromHistoryId
      ),
      CurrentTermStartDate__c = cancelDate,
      CurrentTermEndDate__c = cancelDate,
      EffectiveDate__c = EstimateCreateSupport.parseDate(request.effectiveDate),
      Opportunity__c = opportunity.Id,
      PreviousHistory__c = request.previousHistoryId
    );
    applyEstimateDocumentIfEnabled(contractHistory, request);
    applyEstimateSendContact(contractHistory, request);
    applyContractHistoryCustomFields(contractHistory, request);
    applyNotAutoRenewFieldCopy(contractHistory, request);
    applyOperationKey(contractHistory, request);
    SystemContextAccess.insertRecords(new List<SObject>{ contractHistory });

    return buildSaveResult(
      request.contractServiceId,
      contractHistory.Id,
      contractHistory.Id
    );
  }

  /**
   * Change／Renew／Cancel の Version。最新 Ordered + 1（コピー元 Version は使わない）。
   * copyFromHistoryId は互換のため残す。
   */
  public static Decimal resolveEstimateHistoryVersion(
    Id contractServiceId,
    Id copyFromHistoryId
  ) {
    return ContractHistoryVersionUtil.getNextHistoryVersion(contractServiceId);
  }

  public static List<ContractProduct__c> buildContractProducts(
    Id contractHistoryId,
    Id accountId,
    EstimateCreateController.EstimateSaveRequest request
  ) {
    Map<Id, Product2> productById = loadProductBillingTypes(request.products);
    List<ContractProduct__c> contractProducts = new List<ContractProduct__c>();
    for (EstimateCreateController.ProductLineItem line : request.products) {
      if (line == null || line.productId == null) {
        continue;
      }
      Product2 product = productById.get(line.productId);
      contractProducts.add(
        buildContractProduct(
          contractHistoryId,
          accountId,
          line,
          product,
          request.selectedType,
          EstimateCreateSupport.parseDate(request.effectiveDate)
        )
      );
    }
    return contractProducts;
  }

  public static ContractProduct__c buildContractProduct(
    Id contractHistoryId,
    Id accountId,
    EstimateCreateController.ProductLineItem line,
    Product2 product,
    String selectedType,
    Date effectiveDate
  ) {
    // 明細の課金種別を正とする（New の継続→一回上書きを保存に反映）
    String billingType = String.isNotBlank(line.billingType)
      ? line.billingType
      : (product != null ? product.BillingType__c : null);
    // 仕様: Core 第4.5.2節、第1.1.10節。Change の Original／Remake と Renew 継承は画面 unit（継承元 Unit__c）を優先。
    // 空でも商品マスタから埋めない。Type=New（手追加）は商品マスタから生成する。
    String unitValue;
    Boolean useInheritedUnitSnapshot =
      (selectedType == HISTORY_TYPE_CHANGE &&
        (EstimateCreateSupport.isChangeOriginalLine(line) ||
         EstimateCreateSupport.isChangeRemakeLine(line))) ||
      (selectedType == HISTORY_TYPE_RENEW &&
        line.sourceContractProductId != null);
    if (useInheritedUnitSnapshot) {
      unitValue = line.unit;
    } else {
      unitValue = EstimateCreateSupport.buildDisplayUnit(
        product != null ? product.UnitName__c : null,
        billingType
      );
    }
    // 仕様: Core 第1.1.10節、Accounting 第1.16節
    String revenueBasis;
    try {
      revenueBasis = ContractMetadataService.resolveRevenueRecognitionBasis(
        line.revenueRecognitionBasis
      );
    } catch (ContractMetadataService.RevenueRecognitionBasisException ex) {
      throw EstimateValidationService.wrapAura(ex.getMessage());
    }
    ContractProduct__c contractProduct = new ContractProduct__c(
      ContractHistory__c = contractHistoryId,
      Account__c = accountId,
      Product__c = line.productId,
      Quantity__c = AmountCalculationSettingService.roundQuantityUnitPrice(
        line.quantity
      ),
      UnitPrice__c = AmountCalculationSettingService.roundQuantityUnitPrice(
        line.unitPrice
      ),
      Unit__c = unitValue,
      StartDate__c = EstimateCreateSupport.parseDate(line.startDate),
      Enddate__c = EstimateCreateSupport.parseDate(line.endDate),
      InvoiceSetting__c = ContractMetadataService.normalizeInvoiceSettingLabel(
        line.invoiceType
      ),
      BillingType__c = billingType,
      RevenueRecognitionBasis__c = revenueBasis,
      Type__c = resolveProductType(line, selectedType),
      PreviousContractProduct__c = line.sourceContractProductId
    );
    // 画面で確認した金額を保存。Trigger／Apex で数量×単価へ再計算しない。
    // 仕様: Core 第4.6節、第11.9節
    contractProduct.Amount__c = AmountCalculationSettingService.roundAmount(
      line.amount
    );
    InvoiceAnchorDateUtil.applyToContractProduct(
      contractProduct,
      selectedType,
      effectiveDate
    );
    // Change の Original は処理用打消し行。ウィザード追加項目は載せず、設定済み項目は null クリアする。
    if (
      selectedType == HISTORY_TYPE_CHANGE &&
      EstimateCreateSupport.isChangeOriginalLine(line)
    ) {
      ContractWizardFieldService.applyCustomFields(
        contractProduct,
        ContractWizardFieldService.buildClearedCustomFields(
          ContractWizardFieldService.WizardTarget.ContractProduct
        ),
        ContractWizardFieldService.WizardTarget.ContractProduct
      );
    } else {
      ContractWizardFieldService.applyCustomFields(
        contractProduct,
        ContractWizardFieldService.filterCustomFieldsByVisibility(
          line.customFields,
          ContractWizardFieldService.WizardTarget.ContractProduct,
          // 保存判定の正は常に Product2。クライアントの productVisibilityContext は使わない。
          ContractWizardFieldService.buildProductVisibilityContext(product),
          selectedType
        ),
        ContractWizardFieldService.WizardTarget.ContractProduct
      );
    }
    return contractProduct;
  }

  public static Map<Id, Product2> loadProductBillingTypes(
    List<EstimateCreateController.ProductLineItem> products
  ) {
    Set<Id> productIds = new Set<Id>();
    for (EstimateCreateController.ProductLineItem line : products) {
      if (line.productId != null) {
        productIds.add(line.productId);
      }
    }
    if (productIds.isEmpty()) {
      return new Map<Id, Product2>();
    }

    Set<String> selectFields = new Set<String>{
      'Id',
      'BillingType__c',
      'RevenueRecognitionBasis__c',
      'UnitName__c',
      'AvailableForContract__c'
    };
    selectFields.addAll(
      ContractWizardFieldService.getReferencedProduct2FieldApiNames()
    );
    String soql =
      'SELECT ' +
      String.join(new List<String>(selectFields), ',') +
      ' FROM Product2' +
      ' WHERE Id IN :productIds' +
      ' WITH SYSTEM_MODE';
    return new Map<Id, Product2>((List<Product2>) Database.query(soql));
  }

  public static String resolveProductType(
    EstimateCreateController.ProductLineItem line,
    String selectedType
  ) {
    // Change の Original は recordType=Original を正とする（検証と永続 Type を一致させる）。
    if (
      selectedType == HISTORY_TYPE_CHANGE &&
      EstimateCreateSupport.isChangeOriginalLine(line)
    ) {
      return PRODUCT_TYPE_ORIGINAL;
    }
    if (String.isNotBlank(line.recordType)) {
      return EstimateCreateSupport.normalizeProductRecordType(line.recordType);
    }
    if (selectedType == 'Change') {
      return PRODUCT_TYPE_NEW;
    }
    if (selectedType == 'New') {
      return PRODUCT_TYPE_NEW;
    }
    // 仕様: Core 第4.3.5節。Renewは継承だけ Type=Renew、手追加は Type=New。
    // recordType 空を一律 Renew にしない。継承は sourceContractProductId で区別する。
    if (selectedType == 'Renew') {
      if (line.sourceContractProductId != null) {
        return PRODUCT_TYPE_RENEW;
      }
      return PRODUCT_TYPE_NEW;
    }
    return selectedType;
  }

  public static EstimateCreateController.EstimateSaveResult buildSaveResult(
    Id contractServiceId,
    Id contractHistoryId,
    Id historyIdForProducts
  ) {
    List<ContractProduct__c> savedProducts = [
      SELECT Id
      FROM ContractProduct__c
      WHERE ContractHistory__c = :historyIdForProducts
      WITH SYSTEM_MODE
    ];

    List<Id> productIds = new List<Id>();
    for (ContractProduct__c contractProduct : savedProducts) {
      productIds.add(contractProduct.Id);
    }

    EstimateCreateController.EstimateSaveResult result = new EstimateCreateController.EstimateSaveResult();
    result.contractServiceId = contractServiceId;
    result.contractHistoryId = contractHistoryId;
    result.contractProductIds = productIds;
    if (contractHistoryId != null) {
      List<ContractHistory__c> stamped = [
        SELECT LastModifiedDate, BusinessOperationKey__c
        FROM ContractHistory__c
        WHERE Id = :contractHistoryId
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      if (!stamped.isEmpty()) {
        result.lastModifiedToken = ContractOptimisticLockUtil.toHistoryProductToken(
          contractHistoryId
        );
        result.businessOperationKey = stamped[0].BusinessOperationKey__c;
      }
    }
    return result;
  }

  /** 仕様: 共通基盤.md 第12章 */
  private static EstimateCreateController.EstimateSaveResult writeEstimateLog(
    EstimateCreateController.EstimateSaveRequest request,
    EstimateCreateController.EstimateSaveResult result
  ) {
    if (request == null || result == null) {
      return result;
    }
    String operationType = 'EstimateCreate';
    if (request.editHistoryId != null) {
      operationType = 'EstimateEdit';
    } else if (request.copyFromHistoryId != null) {
      operationType = 'EstimateCopy';
    }
    ContractOperationLogService.write(
      operationType,
      request.businessOperationKey,
      'ContractHistory__c',
      result.contractHistoryId == null
        ? null
        : String.valueOf(result.contractHistoryId)
    );
    return result;
  }

  /** 仕様: Core 第4.3.12節 */
  private static void applyOperationKey(
    ContractHistory__c history,
    EstimateCreateController.EstimateSaveRequest request
  ) {
    if (history == null || request == null) {
      return;
    }
    if (String.isNotBlank(request.businessOperationKey)) {
      history.BusinessOperationKey__c = request.businessOperationKey;
    }
  }

  /** 仕様: Core 第4.3.12節。同じキーの再試行は1件のまま返す。 */
  private static EstimateCreateController.EstimateSaveResult findExistingByOperationKey(
    String operationKey
  ) {
    if (String.isBlank(operationKey)) {
      return null;
    }
    List<ContractHistory__c> found = [
      SELECT Id, ContractService__c
      FROM ContractHistory__c
      WHERE BusinessOperationKey__c = :operationKey
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (found.isEmpty()) {
      return null;
    }
    return buildSaveResult(found[0].ContractService__c, found[0].Id, found[0].Id);
  }

  public static void applyContractServiceCustomFields(
    ContractService__c contractService,
    EstimateCreateController.EstimateSaveRequest request
  ) {
    if (contractService == null || request == null) {
      return;
    }
    ContractWizardFieldService.applyCustomFields(
      contractService,
      ContractWizardFieldService.filterCustomFieldsByVisibility(
        request.contractServiceCustomFields,
        ContractWizardFieldService.WizardTarget.ContractService,
        null,
        request.selectedType
      ),
      ContractWizardFieldService.WizardTarget.ContractService
    );
  }

  public static void applyContractHistoryCustomFields(
    ContractHistory__c contractHistory,
    EstimateCreateController.EstimateSaveRequest request
  ) {
    if (contractHistory == null || request == null) {
      return;
    }
    ContractWizardFieldService.applyCustomFields(
      contractHistory,
      ContractWizardFieldService.filterCustomFieldsByVisibility(
        request.contractHistoryCustomFields,
        ContractWizardFieldService.WizardTarget.ContractHistory,
        null,
        request.selectedType
      ),
      ContractWizardFieldService.WizardTarget.ContractHistory
    );
  }

  public static void mergeApplicationDateIntoHistoryCustomFields(
    EstimateCreateController.EstimateSaveRequest request
  ) {
    if (request == null || String.isBlank(request.applicationDate)) {
      return;
    }
    if (request.contractHistoryCustomFields == null) {
      request.contractHistoryCustomFields = new Map<String, Object>();
    }
    if (
      !request.contractHistoryCustomFields.containsKey('ApplicationDate__c')
    ) {
      request.contractHistoryCustomFields.put(
        'ApplicationDate__c',
        request.applicationDate
      );
    }
  }

  /** 仕様: Core 第4.10節。セクション表示中は空なら Note__c をクリアする。 */
  public static void applyRemarks(
    ContractHistory__c contractHistory,
    String remarksText
  ) {
    if (contractHistory == null) {
      return;
    }
    // 空／未指定はクリア（画面で備考を消して保存したのに Note__c が残るのを防ぐ）
    if (String.isBlank(remarksText)) {
      contractHistory.Note__c = null;
      return;
    }
    if (remarksText.length() > NOTE_MAX_LENGTH) {
      throw EstimateValidationService.wrapAura(
        '見積備考が最大長（' + NOTE_MAX_LENGTH + '文字）を超えています。'
      );
    }
    contractHistory.Note__c = remarksText;
  }

  /** 仕様: Core 第4.10節。空欄は埋めない。送られた値だけ書く。 */
  public static void applyEstimateDocumentDates(
    ContractHistory__c contractHistory,
    EstimateCreateController.EstimateSaveRequest request
  ) {
    if (contractHistory == null || request == null) {
      return;
    }
    contractHistory.EstimateDate__c = EstimateCreateSupport.parseDate(
      request.estimateDate
    );
    contractHistory.EstimateValidDate__c = EstimateCreateSupport.parseDate(
      request.estimateValidDate
    );
  }

  /** 仕様: Core 第4.10節。Cancelも見積書セクションの備考を使う。ここではクリアしない。 */
  public static void applyCancelRemarks(ContractHistory__c contractHistory) {
    if (contractHistory == null) {
      return;
    }
  }

  /** 仕様: Core 第4.10節。`使わない`では見積日・有効期限・備考を保存対象にせず既存を維持する。 */
  @TestVisible
  private static void applyEstimateDocumentIfEnabled(
    ContractHistory__c history,
    EstimateCreateController.EstimateSaveRequest request
  ) {
    if (history == null || request == null) {
      return;
    }
    if (
      ContractDocumentSettingService.requireSendMode('Estimate') ==
      ContractDocumentSettingService.MODE_UNUSED
    ) {
      return;
    }
    history.EstimateNoteMaster__c = request.estimateRemarkMasterId;
    applyRemarks(history, request.remarksText);
    applyEstimateDocumentDates(history, request);
  }

  /** 仕様: Core 第4.3.3節。見積送付先は契約履歴へ保存する。必須にしない。見積書3択には依存しない。 */
  @TestVisible
  private static void applyEstimateSendContact(
    ContractHistory__c history,
    EstimateCreateController.EstimateSaveRequest request
  ) {
    if (history == null || request == null) {
      return;
    }
    history.EstimateSendContact__c = request.estimateSendContactId;
  }

  /** 仕様: Core 第11.4.2節、第4.9節、第4.10節 */
  @TestVisible
  private static void applyNotAutoRenewFieldCopy(
    ContractHistory__c history,
    EstimateCreateController.EstimateSaveRequest request
  ) {
    if (history == null) {
      return;
    }
    Map<String, Object> displayedValues = snapshotDisplayedHistoryFields(
      history,
      request
    );
    Map<String, SObject> sources = new Map<String, SObject>();
    putSource(
      sources,
      'Opportunity',
      InvoiceProductFieldCopyService.querySourceRecord(
        InvoiceProductFieldCopyService.OBJECT_OPPORTUNITY,
        history.Opportunity__c
      )
    );
    SObject opportunity = sources.get('Opportunity');
    if (opportunity != null) {
      putSource(
        sources,
        'Account',
        InvoiceProductFieldCopyService.querySourceRecord(
          InvoiceProductFieldCopyService.OBJECT_ACCOUNT,
          (Id) opportunity.get('AccountId')
        )
      );
    }
    putSource(
      sources,
      'ContractHistory__c',
      InvoiceProductFieldCopyService.querySourceRecord(
        InvoiceProductFieldCopyService.OBJECT_CONTRACT_HISTORY,
        history.PreviousHistory__c
      )
    );
    SObject service = InvoiceProductFieldCopyService.querySourceRecord(
      InvoiceProductFieldCopyService.OBJECT_CONTRACT_SERVICE,
      history.ContractService__c
    );
    putSource(sources, 'ContractService__c', service);
    if (service != null) {
      putSource(
        sources,
        'BillingAccount__c',
        InvoiceProductFieldCopyService.querySourceRecord(
          InvoiceProductFieldCopyService.OBJECT_BILLING_ACCOUNT,
          (Id) service.get('BiilingAcccount__c')
        )
      );
      if (!sources.containsKey('Account')) {
        putSource(
          sources,
          'Account',
          InvoiceProductFieldCopyService.querySourceRecord(
            InvoiceProductFieldCopyService.OBJECT_ACCOUNT,
            (Id) service.get('Account__c')
          )
        );
      }
    }
    FieldCopyDefinitionService.apply(
      history,
      'ContractHistory__c',
      FieldCopyDefinitionService.CONTEXT_NOT_AUTO_RENEW,
      sources
    );
    restoreDisplayedHistoryFields(history, displayedValues);
  }

  /** 仕様: Core 第11.4.2節、第4.3.3節、第4.10節 */
  private static Map<String, Object> snapshotDisplayedHistoryFields(
    ContractHistory__c history,
    EstimateCreateController.EstimateSaveRequest request
  ) {
    Map<String, Object> snapshot = new Map<String, Object>();
    if (history == null) {
      return snapshot;
    }
    String wizardType = request == null ? null : request.selectedType;
    Map<String, Object> displayed = ContractWizardFieldService.filterCustomFieldsByVisibility(
      request == null ? null : request.contractHistoryCustomFields,
      ContractWizardFieldService.WizardTarget.ContractHistory,
      null,
      wizardType
    );
    for (String apiName : displayed.keySet()) {
      snapshot.put(apiName, history.get(apiName));
    }
    // 仕様: Core 第11.4.2節、第4.3.3節。見積送付先はウィザード常時。空でもコピーしない。
    snapshot.put('EstimateSendContact__c', history.EstimateSendContact__c);
    if (
      request != null &&
      ContractDocumentSettingService.requireSendMode('Estimate') !=
        ContractDocumentSettingService.MODE_UNUSED
    ) {
      snapshot.put('EstimateDate__c', history.EstimateDate__c);
      snapshot.put('EstimateValidDate__c', history.EstimateValidDate__c);
      snapshot.put('Note__c', history.Note__c);
      snapshot.put('EstimateNoteMaster__c', history.EstimateNoteMaster__c);
    }
    return snapshot;
  }

  private static void restoreDisplayedHistoryFields(
    ContractHistory__c history,
    Map<String, Object> displayedValues
  ) {
    if (history == null || displayedValues == null || displayedValues.isEmpty()) {
      return;
    }
    for (String apiName : displayedValues.keySet()) {
      history.put(apiName, displayedValues.get(apiName));
    }
  }

  private static void putSource(
    Map<String, SObject> sources,
    String objectApiName,
    SObject record
  ) {
    if (record != null) {
      sources.put(objectApiName, record);
    }
  }
}
