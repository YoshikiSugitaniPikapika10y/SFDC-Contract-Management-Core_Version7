/**
 * 契約サービスの「更新見積自動作成」チェックに応じて Renew 見積を生成する。
 * 発火は OFF→ON の更新時のみ。作成時点から ON では作らない。
 * 元はサービスの最新 Ordered。前商談は見ない。新しい見積の商談は空。
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
  private static final String ORDERED_REQUIRED_MESSAGE = '更新見積自動作成には、この契約サービスの最新の受注（Ordered）が必要です。';
  @TestVisible
  private static final String SPOT_NOT_ALLOWED_MESSAGE = '都度契約（Spot）では更新見積を自動作成できません。';
  @TestVisible
  private static final String RENEW_SOURCE_REQUIRED_MESSAGE = '更新見積自動作成には、前回期間終了日に届く継続課金明細が必要です。';

  public static void validateBeforeSave(
    List<ContractService__c> services,
    Map<Id, ContractService__c> oldMap
  ) {
    List<ContractService__c> targets = selectTargets(services, oldMap);
    if (targets.isEmpty()) {
      return;
    }

    Map<Id, ContractHistory__c> sourceByServiceId = loadSourceHistories(
      collectIds(targets)
    );
    for (ContractService__c service : targets) {
      ContractHistory__c sourceHistory = sourceByServiceId.get(service.Id);
      if (sourceHistory == null) {
        service.addError(ORDERED_REQUIRED_MESSAGE);
        continue;
      }
      if (isSpotOrAddSource(sourceHistory)) {
        service.addError(SPOT_NOT_ALLOWED_MESSAGE);
        continue;
      }
      if (
        EstimateQueryService.countRenewSourceRecurringProducts(
          sourceHistory.Id,
          sourceHistory.CurrentTermEndDate__c
        ) == 0
      ) {
        service.addError(RENEW_SOURCE_REQUIRED_MESSAGE);
      }
    }
  }

  public static void createRenewEstimates(
    List<ContractService__c> services,
    Map<Id, ContractService__c> oldMap
  ) {
    List<ContractService__c> targets = selectTargets(services, oldMap);
    if (targets.isEmpty()) {
      return;
    }

    Map<Id, ContractHistory__c> sourceByServiceId = loadSourceHistories(
      collectIds(targets)
    );
    Set<Id> sourceHistoryIds = new Set<Id>();
    for (ContractHistory__c sourceHistory : sourceByServiceId.values()) {
      sourceHistoryIds.add(sourceHistory.Id);
    }
    Map<Id, List<ContractProduct__c>> productsByHistoryId = loadRenewSourceProducts(
      sourceHistoryIds
    );

    Set<Id> contractServiceIds = new Set<Id>();
    for (ContractService__c service : targets) {
      contractServiceIds.add(service.Id);
    }
    Map<Id, Decimal> versionAllocator = ContractHistoryVersionUtil.buildVersionAllocator(
      contractServiceIds
    );

    List<ContractHistory__c> historiesToInsert = new List<ContractHistory__c>();
    List<RenewEstimateContext> contexts = new List<RenewEstimateContext>();

    for (ContractService__c service : targets) {
      ContractHistory__c sourceHistory = sourceByServiceId.get(service.Id);
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
        Name = String.isBlank(service.Name) ? 'Renew' : service.Name,
        ContractService__c = service.Id,
        Type__c = HISTORY_TYPE_RENEW,
        historystatus__c = HISTORY_STATUS_ESTIMATE,
        Version__c = ContractHistoryVersionUtil.allocateNextVersion(
          versionAllocator,
          service.Id
        ),
        CurrentTermStartDate__c = renewStartDate,
        CurrentTermEndDate__c = renewEndDate,
        EffectiveDate__c = renewStartDate,
        PreviousHistory__c = sourceHistory.Id,
        ApplicationDate__c = sourceHistory.ApplicationDate__c == null
          ? Date.today()
          : sourceHistory.ApplicationDate__c
      );
      historiesToInsert.add(renewHistory);
      contexts.add(
        new RenewEstimateContext(
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
    public ContractHistory__c sourceHistory;
    public ContractHistory__c renewHistory;
    public Date renewStartDate;
    public Date renewEndDate;
    public List<ContractProduct__c> sourceProducts;

    public RenewEstimateContext(
      ContractHistory__c sourceHistory,
      ContractHistory__c renewHistory,
      Date renewStartDate,
      Date renewEndDate,
      List<ContractProduct__c> sourceProducts
    ) {
      this.sourceHistory = sourceHistory;
      this.renewHistory = renewHistory;
      this.renewStartDate = renewStartDate;
      this.renewEndDate = renewEndDate;
      this.sourceProducts = sourceProducts == null
        ? new List<ContractProduct__c>()
        : sourceProducts;
    }
  }

  private static List<ContractService__c> selectTargets(
    List<ContractService__c> services,
    Map<Id, ContractService__c> oldMap
  ) {
    List<ContractService__c> targets = new List<ContractService__c>();
    if (services == null) {
      return targets;
    }
    for (ContractService__c service : services) {
      if (shouldProcess(service, getOldService(service, oldMap))) {
        targets.add(service);
      }
    }
    return targets;
  }

  private static Set<Id> collectIds(List<ContractService__c> services) {
    Set<Id> ids = new Set<Id>();
    for (ContractService__c service : services) {
      if (service.Id != null) {
        ids.add(service.Id);
      }
    }
    return ids;
  }

  private static Boolean shouldProcess(
    ContractService__c service,
    ContractService__c oldService
  ) {
    if (service == null || service.RenewEstimateAutoCreateCheck__c != true) {
      return false;
    }
    if (oldService == null) {
      return false;
    }
    return oldService.RenewEstimateAutoCreateCheck__c != true;
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

  private static ContractService__c getOldService(
    ContractService__c service,
    Map<Id, ContractService__c> oldMap
  ) {
    if (oldMap == null || service == null) {
      return null;
    }
    return oldMap.get(service.Id);
  }

  private static Map<Id, ContractHistory__c> loadSourceHistories(
    Set<Id> serviceIds
  ) {
    Map<Id, ContractHistory__c> sourceByServiceId = new Map<Id, ContractHistory__c>();
    if (serviceIds.isEmpty()) {
      return sourceByServiceId;
    }

    Set<Id> historyIds = new Set<Id>();
    for (ContractService__c service : [
      SELECT Id, LatestOrderedHistory__c
      FROM ContractService__c
      WHERE Id IN :serviceIds
      WITH SYSTEM_MODE
    ]) {
      if (service.LatestOrderedHistory__c != null) {
        historyIds.add(service.LatestOrderedHistory__c);
      }
    }
    if (historyIds.isEmpty()) {
      return sourceByServiceId;
    }

    for (ContractHistory__c history : [
      SELECT
        Id,
        ContractService__c,
        ContractService__r.Lifecycle__c,
        Type__c,
        CurrentTermStartDate__c,
        CurrentTermEndDate__c,
        Version__c,
        ApplicationDate__c
      FROM ContractHistory__c
      WHERE
        Id IN :historyIds
        AND historystatus__c = :HISTORY_STATUS_ORDERED
        AND Type__c IN (
          :HISTORY_TYPE_NEW,
          :HISTORY_TYPE_CHANGE,
          :HISTORY_TYPE_RENEW
        )
      WITH SYSTEM_MODE
    ]) {
      sourceByServiceId.put(history.ContractService__c, history);
    }
    return sourceByServiceId;
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
        AND (BillingType__c = :BILLING_TYPE_RECURRING
        OR (BillingType__c = NULL
        AND Product__r.BillingType__c = :BILLING_TYPE_RECURRING))
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
