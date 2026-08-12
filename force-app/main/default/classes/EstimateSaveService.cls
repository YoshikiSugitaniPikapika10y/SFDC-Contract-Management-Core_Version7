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
  private static final String HISTORY_TYPE_ADD = ContractDomainConstants.HISTORY_TYPE_ADD;
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
    String expectedLastModifiedToken
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
    mergeApplicationDateIntoHistoryCustomFields(request);

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
      return saveEditedEstimate(request, contractHistoryName);
    }

    EstimateValidationService.validateWizardCustomFields(request, false);

    if (request.selectedType == 'New') {
      EstimateValidationService.validateNewSaveRequest(
        request,
        contractHistoryName
      );
      return saveNewEstimate(request, contractHistoryName);
    }

    if (request.selectedType == 'Change') {
      EstimateValidationService.validateChangeSaveRequest(
        request,
        contractHistoryName
      );
      return saveChangeEstimate(request, contractHistoryName);
    }

    if (request.selectedType == 'Renew') {
      EstimateValidationService.validateRenewSaveRequest(
        request,
        contractHistoryName
      );
      return saveChangeEstimate(request, contractHistoryName);
    }

    if (request.selectedType == 'Cancel') {
      EstimateValidationService.validateCancelSaveRequest(
        request,
        contractHistoryName
      );
      return saveCancelEstimate(request, contractHistoryName);
    }

    if (request.selectedType == HISTORY_TYPE_ADD) {
      EstimateValidationService.validateAddSaveRequest(
        request,
        contractHistoryName
      );
      return saveChangeEstimate(request, contractHistoryName);
    }

    throw EstimateValidationService.estSaveException(
      '002',
      'New、Change、Renew、Cancel、Addタイプのみ保存できます。'
    );
  }

  public static EstimateCreateController.EstimateSaveResult saveEditedEstimate(
    EstimateCreateController.EstimateSaveRequest request,
    String contractHistoryName
  ) {
    ContractHistory__c existing = loadEditableEstimateHistory(
      request.editHistoryId
    );
    ContractOptimisticLockUtil.assertHistoryUnchanged(
      existing,
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
      existing.Type__c == 'Cancel' ||
      existing.Type__c == HISTORY_TYPE_ADD
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
    if (request.selectedType == HISTORY_TYPE_ADD) {
      EstimateValidationService.validateAddSaveRequest(
        request,
        contractHistoryName
      );
      return updateChangeEstimate(existing, request, contractHistoryName);
    }

    throw EstimateValidationService.estSaveException(
      '002',
      'New、Change、Renew、Cancel、Addタイプのみ保存できます。'
    );
  }

  public static ContractHistory__c loadEditableEstimateHistory(
    Id editHistoryId
  ) {
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
        LastModifiedDate
      FROM ContractHistory__c
      WHERE Id = :editHistoryId
      WITH SYSTEM_MODE
      LIMIT 1
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

  public static EstimateCreateController.EstimateSaveResult updateOrderedEstimateCustomFieldsOnly(
    ContractHistory__c existing,
    EstimateCreateController.EstimateSaveRequest request
  ) {
    Id serviceId = existing.ContractService__c;
    if (serviceId == null) {
      throw EstimateValidationService.wrapAura('契約サービスが見つかりません。');
    }
    ContractService__c contractService = new ContractService__c(Id = serviceId);
    applyContractServiceCustomFields(contractService, request);
    SystemContextAccess.updateRecords(new List<SObject>{ contractService });

    ContractHistory__c historyUpdate = new ContractHistory__c(Id = existing.Id);
    applyContractHistoryCustomFields(historyUpdate, request);
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
      throw EstimateValidationService.wrapAura('契約サービスが見つかりません。');
    }

    ContractService__c contractService = new ContractService__c(
      Id = serviceId,
      Name = request.contractServiceName,
      BiilingAcccount__c = request.billingAccountId
    );
    applyContractServiceCustomFields(contractService, request);
    SystemContextAccess.updateRecords(new List<SObject>{ contractService });

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
    existing.EstimateNoteMaster__c = request.estimateRemarkMasterId;
    applyRemarks(existing, request.remarksText);
    applyContractHistoryCustomFields(existing, request);
    SystemContextAccess.updateRecords(new List<SObject>{ existing });

    replaceEstimateProducts(existing.Id, opportunity.AccountId, request);

    return buildSaveResult(serviceId, existing.Id, existing.Id);
  }

  public static EstimateCreateController.EstimateSaveResult updateChangeEstimate(
    ContractHistory__c existing,
    EstimateCreateController.EstimateSaveRequest request,
    String contractHistoryName
  ) {
    Id serviceId = existing.ContractService__c;
    if (serviceId == null) {
      throw EstimateValidationService.wrapAura('契約サービスが見つかりません。');
    }
    List<ContractService__c> services = [
      SELECT Id, Account__c
      FROM ContractService__c
      WHERE Id = :serviceId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (services.isEmpty()) {
      throw EstimateValidationService.wrapAura('契約サービスが見つかりません。');
    }

    ContractService__c contractService = new ContractService__c(
      Id = serviceId,
      Name = request.contractServiceName,
      BiilingAcccount__c = request.billingAccountId
    );
    applyContractServiceCustomFields(contractService, request);
    SystemContextAccess.updateRecords(new List<SObject>{ contractService });

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
    existing.EstimateNoteMaster__c = request.estimateRemarkMasterId;
    applyRemarks(existing, request.remarksText);
    applyContractHistoryCustomFields(existing, request);
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
    if (serviceId != null) {
      ContractService__c contractService = new ContractService__c(
        Id = serviceId,
        Name = request.contractServiceName,
        BiilingAcccount__c = request.billingAccountId
      );
      applyContractServiceCustomFields(contractService, request);
      SystemContextAccess.updateRecords(new List<SObject>{ contractService });
    }

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
    // Cancel は備考マスタ／自由文を登録しない（ペイロードがあっても常にクリア）。
    applyCancelRemarks(existing);
    applyContractHistoryCustomFields(existing, request);
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

  public static EstimateCreateController.EstimateSaveResult saveNewEstimate(
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

    Date serviceStartDate = EstimateCreateSupport.parseDate(
      request.contractStartDate
    );
    Date serviceEndDate = EstimateCreateSupport.parseDate(
      request.contractEndDate
    );

    ContractService__c contractService = new ContractService__c(
      Name = request.contractServiceName,
      Account__c = opportunity.AccountId,
      BiilingAcccount__c = request.billingAccountId
    );
    applyContractServiceCustomFields(contractService, request);
    SystemContextAccess.insertRecords(new List<SObject>{ contractService });

    ContractHistory__c contractHistory = new ContractHistory__c(
      Name = contractHistoryName,
      ContractService__c = contractService.Id,
      Type__c = request.selectedType,
      historystatus__c = HISTORY_STATUS_ESTIMATE,
      Version__c = 1,
      CurrentTermStartDate__c = serviceStartDate,
      CurrentTermEndDate__c = serviceEndDate,
      EffectiveDate__c = EstimateCreateSupport.parseDate(request.effectiveDate),
      Opportunity__c = opportunity.Id,
      EstimateNoteMaster__c = request.estimateRemarkMasterId
    );
    applyRemarks(contractHistory, request.remarksText);
    applyContractHistoryCustomFields(contractHistory, request);
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
      throw EstimateValidationService.wrapAura('契約サービスが見つかりません。');
    }

    ContractService__c contractService = new ContractService__c(
      Id = request.contractServiceId,
      Name = request.contractServiceName,
      BiilingAcccount__c = request.billingAccountId
    );
    applyContractServiceCustomFields(contractService, request);
    SystemContextAccess.updateRecords(new List<SObject>{ contractService });

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
      PreviousHistory__c = request.previousHistoryId,
      EstimateNoteMaster__c = request.estimateRemarkMasterId
    );
    applyRemarks(contractHistory, request.remarksText);
    applyContractHistoryCustomFields(contractHistory, request);
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
      throw EstimateValidationService.wrapAura('契約サービスが見つかりません。');
    }

    ContractService__c contractService = new ContractService__c(
      Id = request.contractServiceId,
      Name = request.contractServiceName,
      BiilingAcccount__c = request.billingAccountId
    );
    applyContractServiceCustomFields(contractService, request);
    SystemContextAccess.updateRecords(new List<SObject>{ contractService });

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
    // Cancel は備考マスタ／自由文を登録しない（ペイロードがあっても常にクリア）。
    applyCancelRemarks(contractHistory);
    applyContractHistoryCustomFields(contractHistory, request);
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
    String unitName = product != null ? product.UnitName__c : null;
    ContractProduct__c contractProduct = new ContractProduct__c(
      ContractHistory__c = contractHistoryId,
      Account__c = accountId,
      Product__c = line.productId,
      Quantity__c = line.quantity == null
        ? null
        : line.quantity.setScale(2, RoundingMode.HALF_UP),
      UnitPrice__c = line.unitPrice == null
        ? null
        : line.unitPrice.setScale(2, RoundingMode.HALF_UP),
      Unit__c = EstimateCreateSupport.buildDisplayUnit(unitName, billingType),
      StartDate__c = EstimateCreateSupport.parseDate(line.startDate),
      Enddate__c = EstimateCreateSupport.parseDate(line.endDate),
      InvoiceSetting__c = ContractMetadataService.normalizeInvoiceSettingLabel(
        line.invoiceType
      ),
      BillingType__c = billingType,
      Type__c = resolveProductType(line, selectedType),
      PreviousContractProduct__c = line.sourceContractProductId
    );
    // 画面で確認した金額を保存（整数円）。Trigger／Apex で数量×単価へ再計算しない。
    contractProduct.Amount__c = line.amount == null
      ? null
      : line.amount.setScale(0, RoundingMode.HALF_UP);
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
    if (selectedType == 'Renew') {
      return PRODUCT_TYPE_RENEW;
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
        SELECT LastModifiedDate
        FROM ContractHistory__c
        WHERE Id = :contractHistoryId
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      if (!stamped.isEmpty()) {
        result.lastModifiedToken = ContractOptimisticLockUtil.toToken(
          stamped[0].LastModifiedDate
        );
      }
    }
    return result;
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
    contractHistory.Note__c = remarksText.length() > NOTE_MAX_LENGTH
      ? remarksText.substring(0, NOTE_MAX_LENGTH)
      : remarksText;
  }

  /**
   * Cancel は備考 UI なし。ペイロードにマスタ／文言があっても
   * EstimateNoteMaster__c / Note__c は登録・残存させない。
   */
  public static void applyCancelRemarks(ContractHistory__c contractHistory) {
    if (contractHistory == null) {
      return;
    }
    contractHistory.EstimateNoteMaster__c = null;
    contractHistory.Note__c = null;
  }
}
