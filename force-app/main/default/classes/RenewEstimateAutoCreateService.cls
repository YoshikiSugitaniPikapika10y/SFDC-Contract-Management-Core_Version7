/**
 * 商談の「更新見積自動作成」チェック（RenewEstimateAutoCreateCheck__c）に応じて
 * Renew 見積の契約履歴・商品を生成する。
 *
 * 発火条件は OFF→ON への更新時のみ。商談の新規作成時（作成時点からチェック ON）では作らない。
 */
public without sharing class RenewEstimateAutoCreateService {
  private static final String HISTORY_STATUS_ESTIMATE = ContractDomainConstants.HISTORY_STATUS_ESTIMATE;
  private static final String HISTORY_STATUS_ORDERED = ContractDomainConstants.HISTORY_STATUS_ORDERED;
  private static final String HISTORY_TYPE_NEW = ContractDomainConstants.HISTORY_TYPE_NEW;
  private static final String HISTORY_TYPE_CHANGE = ContractDomainConstants.HISTORY_TYPE_CHANGE;
  private static final String HISTORY_TYPE_RENEW = ContractDomainConstants.HISTORY_TYPE_RENEW;
  private static final String HISTORY_TYPE_ADD = ContractDomainConstants.HISTORY_TYPE_ADD;
  private static final String PRODUCT_TYPE_RENEW = ContractDomainConstants.PRODUCT_TYPE_RENEW;
  private static final String PRODUCT_TYPE_REMAKE = ContractDomainConstants.PRODUCT_TYPE_REMAKE;
  private static final String PRODUCT_TYPE_NEW = ContractDomainConstants.PRODUCT_TYPE_NEW;
  private static final String BILLING_TYPE_RECURRING = ContractDomainConstants.BILLING_TYPE_RECURRING;
  @TestVisible
  private static final String ORDERED_REQUIRED_MESSAGE = '更新見積自動作成には前商談の Ordered 契約履歴が必須です。';
  @TestVisible
  private static final String PREVIOUS_OPPORTUNITY_REQUIRED_MESSAGE = '更新見積自動作成には前商談を設定してください。';
  @TestVisible
  private static final String SPOT_NOT_ALLOWED_MESSAGE = '都度契約（Spot）では更新見積を自動作成できません。';
  @TestVisible
  private static final String RENEW_SOURCE_REQUIRED_MESSAGE = '更新見積自動作成には、前回期間終了日に届く継続課金明細が必要です。';

  public static void validateBeforeSave(
    List<Opportunity> opportunities,
    Map<Id, Opportunity> oldMap
  ) {
    Set<Id> previousOppIds = new Set<Id>();
    for (Opportunity opportunity : opportunities) {
      if (!shouldProcess(opportunity, getOldOpportunity(opportunity, oldMap))) {
        continue;
      }
      if (opportunity.PreviousOpportunity__c == null) {
        opportunity.addError(PREVIOUS_OPPORTUNITY_REQUIRED_MESSAGE);
        continue;
      }
      previousOppIds.add(opportunity.PreviousOpportunity__c);
    }
    if (previousOppIds.isEmpty()) {
      return;
    }

    Map<Id, ContractHistory__c> sourceByPreviousOpp = loadSourceHistories(
      previousOppIds
    );
    for (Opportunity opportunity : opportunities) {
      if (!shouldProcess(opportunity, getOldOpportunity(opportunity, oldMap))) {
        continue;
      }
      if (opportunity.PreviousOpportunity__c == null) {
        continue;
      }
      if (
        !sourceByPreviousOpp.containsKey(opportunity.PreviousOpportunity__c)
      ) {
        opportunity.addError(ORDERED_REQUIRED_MESSAGE);
        continue;
      }
      if (
        isSpotOrAddSource(
          sourceByPreviousOpp.get(opportunity.PreviousOpportunity__c)
        )
      ) {
        opportunity.addError(SPOT_NOT_ALLOWED_MESSAGE);
        continue;
      }
      ContractHistory__c sourceHistory = sourceByPreviousOpp.get(
        opportunity.PreviousOpportunity__c
      );
      if (
        EstimateQueryService.countRenewSourceRecurringProducts(
          sourceHistory.Id,
          sourceHistory.CurrentTermEndDate__c
        ) == 0
      ) {
        opportunity.addError(RENEW_SOURCE_REQUIRED_MESSAGE);
      }
    }
  }

  public static void createRenewEstimates(
    List<Opportunity> opportunities,
    Map<Id, Opportunity> oldMap
  ) {
    List<Opportunity> targets = new List<Opportunity>();
    for (Opportunity opportunity : opportunities) {
      if (shouldProcess(opportunity, getOldOpportunity(opportunity, oldMap))) {
        targets.add(opportunity);
      }
    }
    if (targets.isEmpty()) {
      return;
    }

    Set<Id> previousOppIds = new Set<Id>();
    for (Opportunity opportunity : targets) {
      if (opportunity.PreviousOpportunity__c != null) {
        previousOppIds.add(opportunity.PreviousOpportunity__c);
      }
    }

    Map<Id, ContractHistory__c> sourceByPreviousOpp = loadSourceHistories(
      previousOppIds
    );
    Set<Id> sourceHistoryIds = new Set<Id>();
    for (ContractHistory__c sourceHistory : sourceByPreviousOpp.values()) {
      sourceHistoryIds.add(sourceHistory.Id);
    }
    Map<Id, List<ContractProduct__c>> productsByHistoryId = loadRenewSourceProducts(
      sourceHistoryIds
    );

    Set<Id> contractServiceIds = new Set<Id>();
    for (ContractHistory__c sourceHistory : sourceByPreviousOpp.values()) {
      if (sourceHistory.ContractService__c != null) {
        contractServiceIds.add(sourceHistory.ContractService__c);
      }
    }
    Map<Id, Decimal> versionAllocator = ContractHistoryVersionUtil.buildVersionAllocator(
      contractServiceIds
    );

    List<ContractHistory__c> historiesToInsert = new List<ContractHistory__c>();
    List<RenewEstimateContext> contexts = new List<RenewEstimateContext>();

    for (Opportunity opportunity : targets) {
      if (opportunity.PreviousOpportunity__c == null) {
        continue;
      }

      ContractHistory__c sourceHistory = sourceByPreviousOpp.get(
        opportunity.PreviousOpportunity__c
      );
      if (
        sourceHistory == null ||
        sourceHistory.CurrentTermEndDate__c == null ||
        isSpotOrAddSource(sourceHistory)
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
        12
      );
      ContractHistory__c renewHistory = new ContractHistory__c(
        Name = opportunity.Name,
        ContractService__c = sourceHistory.ContractService__c,
        Type__c = HISTORY_TYPE_RENEW,
        historystatus__c = HISTORY_STATUS_ESTIMATE,
        Version__c = ContractHistoryVersionUtil.allocateNextVersion(
          versionAllocator,
          sourceHistory.ContractService__c
        ),
        CurrentTermStartDate__c = renewStartDate,
        CurrentTermEndDate__c = renewEndDate,
        EffectiveDate__c = renewStartDate,
        Opportunity__c = opportunity.Id,
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

    SystemContextAccess.insertRecords(historiesToInsert);

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

  private static Boolean shouldProcess(
    Opportunity opportunity,
    Opportunity oldOpportunity
  ) {
    if (opportunity.RenewEstimateAutoCreateCheck__c != true) {
      return false;
    }
    // 新規作成時（oldOpportunity なし）はチェック済みで作成されても発火しない。
    // OFF→ON への更新時のみ処理対象とする。
    if (oldOpportunity == null) {
      return false;
    }
    return oldOpportunity.RenewEstimateAutoCreateCheck__c != true;
  }

  private static Boolean isSpotOrAddSource(ContractHistory__c sourceHistory) {
    if (sourceHistory == null) {
      return false;
    }
    if (sourceHistory.Type__c == HISTORY_TYPE_ADD) {
      return true;
    }
    String lifecycle = sourceHistory.ContractService__r == null
      ? null
      : sourceHistory.ContractService__r.Lifecycle__c;
    return ContractServiceLifecycleService.isSpotLifecycle(lifecycle);
  }

  private static Opportunity getOldOpportunity(
    Opportunity opportunity,
    Map<Id, Opportunity> oldMap
  ) {
    if (oldMap == null) {
      return null;
    }
    return oldMap.get(opportunity.Id);
  }

  private static Map<Id, ContractHistory__c> loadSourceHistories(
    Set<Id> previousOppIds
  ) {
    Map<Id, ContractHistory__c> sourceByPreviousOpp = new Map<Id, ContractHistory__c>();
    if (previousOppIds.isEmpty()) {
      return sourceByPreviousOpp;
    }

    for (ContractHistory__c history : [
      SELECT
        Id,
        Opportunity__c,
        ContractService__c,
        ContractService__r.Lifecycle__c,
        Type__c,
        CurrentTermStartDate__c,
        CurrentTermEndDate__c,
        Version__c
      FROM ContractHistory__c
      WHERE
        Opportunity__c IN :previousOppIds
        AND historystatus__c = :HISTORY_STATUS_ORDERED
        AND Type__c IN (
          :HISTORY_TYPE_NEW,
          :HISTORY_TYPE_CHANGE,
          :HISTORY_TYPE_RENEW
        )
      WITH SYSTEM_MODE
      ORDER BY Version__c DESC NULLS LAST
    ]) {
      if (!sourceByPreviousOpp.containsKey(history.Opportunity__c)) {
        sourceByPreviousOpp.put(history.Opportunity__c, history);
      }
    }
    return sourceByPreviousOpp;
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
        BillingType__c,
        Unit__c,
        UnitPrice__c,
        Quantity__c,
        InvoiceSetting__c,
        Enddate__c,
        Type__c
      FROM ContractProduct__c
      WHERE
        ContractHistory__c IN :sourceHistoryIds
        AND (
          BillingType__c = :BILLING_TYPE_RECURRING
          OR (
            BillingType__c = NULL
            AND Product__r.BillingType__c = :BILLING_TYPE_RECURRING
          )
        )
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
      ORDER BY Name ASC
    ]) {
      // 期末到達のみ（手動 Renew の Enddate__c = termEndDate と同じ）
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

  private static ContractProduct__c buildRenewContractProduct(
    Id renewHistoryId,
    Date renewStartDate,
    Date renewEndDate,
    ContractProduct__c sourceProduct
  ) {
    String billingType = ContractMetadataService.resolveLineBillingType(
      sourceProduct
    );
    Decimal quantity = sourceProduct.Quantity__c == null
      ? null
      : sourceProduct.Quantity__c.setScale(2, RoundingMode.HALF_UP);
    Decimal unitPrice = sourceProduct.UnitPrice__c == null
      ? null
      : sourceProduct.UnitPrice__c.setScale(2, RoundingMode.HALF_UP);
    // 見積金額正本。未保存のまま受注されても見積バー／発生金額が 0 にならないよう必ずセットする。
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
