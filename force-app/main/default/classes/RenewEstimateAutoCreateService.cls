/**
 * 受注時に作成された更新商談を起点に Renew 見積を生成する。
 * 更新商談の SourceContractHistory__c と ContractService__c を正とし、
 * 作成した Renew 見積をその更新商談へ必ず紐づける。
 */
public without sharing class RenewEstimateAutoCreateService {
  private static final String HISTORY_STATUS_ESTIMATE = ContractDomainConstants.HISTORY_STATUS_ESTIMATE;
  private static final String HISTORY_STATUS_ORDERED = ContractDomainConstants.HISTORY_STATUS_ORDERED;
  private static final String HISTORY_TYPE_NEW = ContractDomainConstants.HISTORY_TYPE_NEW;
  private static final String HISTORY_TYPE_CHANGE = ContractDomainConstants.HISTORY_TYPE_CHANGE;
  private static final String HISTORY_TYPE_RENEW = ContractDomainConstants.HISTORY_TYPE_RENEW;
  private static final String PRODUCT_TYPE_RENEW = ContractDomainConstants.PRODUCT_TYPE_RENEW;
  private static final String PRODUCT_TYPE_REMAKE = ContractDomainConstants.PRODUCT_TYPE_REMAKE;
  private static final String PRODUCT_TYPE_NEW = ContractDomainConstants.PRODUCT_TYPE_NEW;
  private static final String BILLING_TYPE_RECURRING = ContractDomainConstants.BILLING_TYPE_RECURRING;
  @TestVisible
  private static final String ORDERED_REQUIRED_MESSAGE = '更新見積自動作成には、更新商談の元契約履歴が受注済みである必要があります。';
  @TestVisible
  private static final String SPOT_NOT_ALLOWED_MESSAGE = '都度契約（Spot）では更新見積を自動作成できません。';
  @TestVisible
  private static final String RENEW_SOURCE_REQUIRED_MESSAGE = '更新見積自動作成には、前回期間終了日に届く継続課金明細が必要です。';
  @TestVisible
  private static final String CONTRACT_SERVICE_REQUIRED_MESSAGE = '更新商談には契約サービスが必要です。';
  @TestVisible
  private static final String CONTRACT_SERVICE_MISMATCH_MESSAGE = '更新商談の契約サービスが元契約履歴と一致しません。';
  @TestVisible
  private static final String ACCOUNT_MISMATCH_MESSAGE = '更新商談の取引先が契約サービスの取引先と一致しません。';

  public static void validateRenewOpportunities(List<Opportunity> opportunities) {
    List<Opportunity> targets = selectTargets(opportunities);
    if (targets.isEmpty()) {
      return;
    }

    Map<Id, ContractHistory__c> sourceById = loadSourceHistories(
      collectSourceHistoryIds(targets)
    );
    Map<Id, List<ContractProduct__c>> productsByHistoryId = loadRenewSourceProducts(
      sourceById.keySet()
    );
    for (Opportunity opportunity : targets) {
      if (opportunity.ContractService__c == null) {
        opportunity.addError(CONTRACT_SERVICE_REQUIRED_MESSAGE);
        continue;
      }
      ContractHistory__c sourceHistory = sourceById.get(
        opportunity.SourceContractHistory__c
      );
      if (
        sourceHistory == null ||
        sourceHistory.historystatus__c != HISTORY_STATUS_ORDERED
      ) {
        opportunity.addError(ORDERED_REQUIRED_MESSAGE);
        continue;
      }
      if (sourceHistory.ContractService__c != opportunity.ContractService__c) {
        opportunity.addError(CONTRACT_SERVICE_MISMATCH_MESSAGE);
        continue;
      }
      if (
        sourceHistory.ContractService__r != null &&
        sourceHistory.ContractService__r.Account__c != opportunity.AccountId
      ) {
        opportunity.addError(ACCOUNT_MISMATCH_MESSAGE);
        continue;
      }
      if (isSpotSource(sourceHistory)) {
        opportunity.addError(SPOT_NOT_ALLOWED_MESSAGE);
        continue;
      }
      List<ContractProduct__c> sourceProducts = productsByHistoryId.get(
        sourceHistory.Id
      );
      if (sourceProducts == null || sourceProducts.isEmpty()) {
        opportunity.addError(RENEW_SOURCE_REQUIRED_MESSAGE);
      }
    }
  }

  /** 仕様: Core 第4.9節、第11.5節 */
  public static void createRenewEstimates(List<Opportunity> opportunities) {
    if (!ContractDocumentSettingService.requireRenewOpportunitySwitch()) {
      return;
    }
    // 仕様: Core 第11.4.2節
    FieldCopyDefinitionService.validateAllDefinitions();
    List<Opportunity> targets = selectTargets(opportunities);
    if (targets.isEmpty()) {
      return;
    }

    Map<Id, ContractHistory__c> sourceById = loadSourceHistories(
      collectSourceHistoryIds(targets)
    );
    Map<Id, List<ContractProduct__c>> productsByHistoryId = loadRenewSourceProducts(
      sourceById.keySet()
    );

    Set<Id> contractServiceIds = new Set<Id>();
    for (Opportunity opportunity : targets) {
      contractServiceIds.add(opportunity.ContractService__c);
    }
    Map<Id, Decimal> versionAllocator = ContractHistoryVersionUtil.buildVersionAllocator(
      contractServiceIds
    );

    List<ContractHistory__c> historiesToInsert = new List<ContractHistory__c>();
    List<RenewEstimateContext> contexts = new List<RenewEstimateContext>();

    for (Opportunity opportunity : targets) {
      ContractHistory__c sourceHistory = sourceById.get(
        opportunity.SourceContractHistory__c
      );
      if (
        sourceHistory == null ||
        sourceHistory.CurrentTermEndDate__c == null ||
        isSpotSource(sourceHistory)
      ) {
        continue;
      }
      List<ContractProduct__c> sourceProducts = productsByHistoryId.get(
        sourceHistory.Id
      );
      if (sourceProducts == null || sourceProducts.isEmpty()) {
        continue;
      }

      Date renewStartDate = sourceHistory.CurrentTermEndDate__c.addDays(1);
      Date renewEndDate = MonthlyBillingPeriodUtil.endDateForMonthlyCycles(
        renewStartDate,
        ContractDocumentSettingService.requireDefaultCycles()
      );
      ContractHistory__c renewHistory = new ContractHistory__c(
        Name = String.isBlank(opportunity.Name) ? 'Renew' : opportunity.Name,
        ContractService__c = opportunity.ContractService__c,
        Opportunity__c = opportunity.Id,
        Type__c = HISTORY_TYPE_RENEW,
        historystatus__c = HISTORY_STATUS_ESTIMATE,
        RenewEstimateAutoCreated__c = true,
        Version__c = ContractHistoryVersionUtil.allocateNextVersion(
          versionAllocator,
          opportunity.ContractService__c
        ),
        CurrentTermStartDate__c = renewStartDate,
        CurrentTermEndDate__c = renewEndDate,
        EffectiveDate__c = renewStartDate,
        PreviousHistory__c = sourceHistory.Id
      );
      historiesToInsert.add(renewHistory);
      contexts.add(
        new RenewEstimateContext(
          opportunity,
          sourceHistory,
          renewHistory,
          renewStartDate,
          renewEndDate,
          sourceProducts
        )
      );
    }

    if (historiesToInsert.isEmpty()) {
      return;
    }

    for (RenewEstimateContext context : contexts) {
      applyAutoRenewFieldCopy(context);
    }

    Boolean previousAllow = ContractHistoryTriggerHandler.allowRenewEstimateAutoCreatedWrite;
    ContractHistoryTriggerHandler.allowRenewEstimateAutoCreatedWrite = true;
    try {
      SystemContextAccess.insertRecords(historiesToInsert);
    } finally {
      ContractHistoryTriggerHandler.allowRenewEstimateAutoCreatedWrite = previousAllow;
    }

    List<ContractProduct__c> productsToInsert = new List<ContractProduct__c>();
    for (RenewEstimateContext context : contexts) {
      productsToInsert.addAll(
        buildRenewProducts(
          context.renewHistory.Id,
          context.renewStartDate,
          context.renewEndDate,
          context.sourceProducts
        )
      );
    }
    if (!productsToInsert.isEmpty()) {
      SystemContextAccess.insertRecords(productsToInsert);
    }
  }

  private class RenewEstimateContext {
    public Opportunity opportunity;
    public ContractHistory__c sourceHistory;
    public ContractHistory__c renewHistory;
    public Date renewStartDate;
    public Date renewEndDate;
    public List<ContractProduct__c> sourceProducts;

    public RenewEstimateContext(
      Opportunity opportunity,
      ContractHistory__c sourceHistory,
      ContractHistory__c renewHistory,
      Date renewStartDate,
      Date renewEndDate,
      List<ContractProduct__c> sourceProducts
    ) {
      this.opportunity = opportunity;
      this.sourceHistory = sourceHistory;
      this.renewHistory = renewHistory;
      this.renewStartDate = renewStartDate;
      this.renewEndDate = renewEndDate;
      this.sourceProducts = sourceProducts == null
        ? new List<ContractProduct__c>()
        : sourceProducts;
    }
  }

  /** 仕様: Core 第11.4.2節、第4.9節 */
  private static void applyAutoRenewFieldCopy(RenewEstimateContext context) {
    if (context == null || context.renewHistory == null) {
      return;
    }
    Map<String, SObject> sources = new Map<String, SObject>();
    if (context.opportunity != null) {
      SObject opportunity = InvoiceProductFieldCopyService.querySourceRecord(
        InvoiceProductFieldCopyService.OBJECT_OPPORTUNITY,
        context.opportunity.Id
      );
      if (opportunity != null) {
        sources.put('Opportunity', opportunity);
        Id accountId = (Id) opportunity.get('AccountId');
        if (accountId != null) {
          SObject account = InvoiceProductFieldCopyService.querySourceRecord(
            InvoiceProductFieldCopyService.OBJECT_ACCOUNT,
            accountId
          );
          if (account != null) {
            sources.put('Account', account);
          }
        }
      }
    }
    if (context.sourceHistory != null) {
      SObject previous = InvoiceProductFieldCopyService.querySourceRecord(
        InvoiceProductFieldCopyService.OBJECT_CONTRACT_HISTORY,
        context.sourceHistory.Id
      );
      if (previous != null) {
        sources.put('ContractHistory__c', previous);
      }
      SObject service = InvoiceProductFieldCopyService.querySourceRecord(
        InvoiceProductFieldCopyService.OBJECT_CONTRACT_SERVICE,
        context.sourceHistory.ContractService__c
      );
      if (service != null) {
        sources.put('ContractService__c', service);
        Id baId = (Id) service.get('BiilingAcccount__c');
        if (baId != null) {
          SObject billing = InvoiceProductFieldCopyService.querySourceRecord(
            InvoiceProductFieldCopyService.OBJECT_BILLING_ACCOUNT,
            baId
          );
          if (billing != null) {
            sources.put('BillingAccount__c', billing);
          }
        }
        if (!sources.containsKey('Account')) {
          Id accountId = (Id) service.get('Account__c');
          if (accountId != null) {
            SObject account = InvoiceProductFieldCopyService.querySourceRecord(
              InvoiceProductFieldCopyService.OBJECT_ACCOUNT,
              accountId
            );
            if (account != null) {
              sources.put('Account', account);
            }
          }
        }
      }
    }
    FieldCopyDefinitionService.apply(
      context.renewHistory,
      'ContractHistory__c',
      FieldCopyDefinitionService.CONTEXT_AUTO_RENEW,
      sources
    );
  }

  private static List<Opportunity> selectTargets(
    List<Opportunity> opportunities
  ) {
    List<Opportunity> targets = new List<Opportunity>();
    if (opportunities == null) {
      return targets;
    }
    for (Opportunity opportunity : opportunities) {
      if (
        opportunity != null &&
        opportunity.SourceContractHistory__c != null
      ) {
        targets.add(opportunity);
      }
    }
    return targets;
  }

  private static Set<Id> collectSourceHistoryIds(
    List<Opportunity> opportunities
  ) {
    Set<Id> ids = new Set<Id>();
    for (Opportunity opportunity : opportunities) {
      if (opportunity.SourceContractHistory__c != null) {
        ids.add(opportunity.SourceContractHistory__c);
      }
    }
    return ids;
  }

  private static Boolean isSpotSource(ContractHistory__c sourceHistory) {
    if (sourceHistory == null) {
      return false;
    }
    String lifecycle = sourceHistory.ContractService__r == null
      ? null
      : sourceHistory.ContractService__r.Lifecycle__c;
    return ContractServiceLifecycleService.isSpotLifecycle(lifecycle);
  }

  private static Map<Id, ContractHistory__c> loadSourceHistories(
    Set<Id> historyIds
  ) {
    Map<Id, ContractHistory__c> sourceById = new Map<Id, ContractHistory__c>();
    if (historyIds.isEmpty()) {
      return sourceById;
    }

    for (ContractHistory__c history : [
      SELECT
        Id,
        ContractService__c,
        ContractService__r.Lifecycle__c,
        ContractService__r.Account__c,
        Type__c,
        historystatus__c,
        CurrentTermStartDate__c,
        CurrentTermEndDate__c,
        Version__c,
        ApplicationDate__c
      FROM ContractHistory__c
      WHERE Id IN :historyIds
      WITH SYSTEM_MODE
    ]) {
      sourceById.put(history.Id, history);
    }
    return sourceById;
  }

  /**
   * 手動 Renew（EstimateQueryService.getRenewContractProducts）と同じ候補。
   * 継続課金・数量>0・期末到達・Type が Remake/New/Renew（または空）のみ。
   * Change の Original（打消し行）は引き継がない。
   */
  private static Map<Id, List<ContractProduct__c>> loadRenewSourceProducts(
    Set<Id> sourceHistoryIds
  ) {
    Map<Id, List<ContractProduct__c>> productsByHistoryId = new Map<Id, List<ContractProduct__c>>();
    if (sourceHistoryIds.isEmpty()) {
      return productsByHistoryId;
    }

    for (ContractProduct__c product : [
      SELECT
        Id,
        ContractHistory__c,
        ContractHistory__r.CurrentTermEndDate__c,
        Account__c,
        Product__c,
        Product__r.BillingType__c,
        Product__r.RevenueRecognitionBasis__c,
        BillingType__c,
        RevenueRecognitionBasis__c,
        Unit__c,
        UnitPrice__c,
        Quantity__c,
        InvoiceSetting__c,
        Enddate__c,
        Type__c
      FROM ContractProduct__c
      WHERE
        ContractHistory__c IN :sourceHistoryIds
        AND BillingType__c = :BILLING_TYPE_RECURRING
        AND Quantity__c > 0
        AND (Type__c = NULL
        OR Type__c IN (
          :PRODUCT_TYPE_REMAKE,
          :PRODUCT_TYPE_NEW,
          :PRODUCT_TYPE_RENEW
        ))
      WITH SYSTEM_MODE
      ORDER BY Name ASC
    ]) {
      if (
        product.Enddate__c == null ||
        product.ContractHistory__r == null ||
        product.Enddate__c != product.ContractHistory__r.CurrentTermEndDate__c
      ) {
        continue;
      }
      if (!productsByHistoryId.containsKey(product.ContractHistory__c)) {
        productsByHistoryId.put(
          product.ContractHistory__c,
          new List<ContractProduct__c>()
        );
      }
      productsByHistoryId.get(product.ContractHistory__c).add(product);
    }
    return productsByHistoryId;
  }

  private static List<ContractProduct__c> buildRenewProducts(
    Id renewHistoryId,
    Date renewStartDate,
    Date renewEndDate,
    List<ContractProduct__c> sourceProducts
  ) {
    List<ContractProduct__c> products = new List<ContractProduct__c>();
    for (ContractProduct__c sourceProduct : sourceProducts) {
      products.add(
        buildRenewContractProduct(
          renewHistoryId,
          renewStartDate,
          renewEndDate,
          sourceProduct
        )
      );
    }
    return products;
  }

  /** 仕様: Core 第4.9節、第4.6節、第11.9節 */
  private static ContractProduct__c buildRenewContractProduct(
    Id renewHistoryId,
    Date renewStartDate,
    Date renewEndDate,
    ContractProduct__c sourceProduct
  ) {
    String billingType = ContractMetadataService.resolveLineBillingType(
      sourceProduct
    );
    Decimal quantity = AmountCalculationSettingService.roundQuantityUnitPrice(
      sourceProduct.Quantity__c
    );
    Decimal unitPrice = AmountCalculationSettingService.roundQuantityUnitPrice(
      sourceProduct.UnitPrice__c
    );
    Decimal amount = ContractProductAmountUtil.calculateUnsignedAmount(
      quantity,
      unitPrice,
      billingType,
      renewStartDate,
      renewEndDate
    );
    ContractProduct__c product = new ContractProduct__c(
      ContractHistory__c = renewHistoryId,
      Account__c = sourceProduct.Account__c,
      Product__c = sourceProduct.Product__c,
      Quantity__c = quantity,
      UnitPrice__c = unitPrice,
      Amount__c = amount,
      Unit__c = sourceProduct.Unit__c,
      StartDate__c = renewStartDate,
      Enddate__c = renewEndDate,
      InvoiceSetting__c = sourceProduct.InvoiceSetting__c,
      BillingType__c = billingType,
      RevenueRecognitionBasis__c = ContractMetadataService.resolveLineRevenueRecognitionBasis(
        sourceProduct
      ),
      Type__c = PRODUCT_TYPE_RENEW,
      PreviousContractProduct__c = sourceProduct.Id
    );
    InvoiceAnchorDateUtil.applyToContractProduct(
      product,
      ContractDomainConstants.HISTORY_TYPE_RENEW,
      renewStartDate
    );
    return product;
  }
}
