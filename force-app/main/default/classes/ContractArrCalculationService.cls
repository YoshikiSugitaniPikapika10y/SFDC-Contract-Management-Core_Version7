/**
 * 契約履歴の ARR（期末ランレート）／AveARR（期間平均ランレート）再計算。
 * DeltaARR__c / DeltaAveARR__c は数式項目とし、このサービスからは書き込まない。
 */
public without sharing class ContractArrCalculationService {
  private static final String BILLING_TYPE_RECURRING = ContractDomainConstants.BILLING_TYPE_RECURRING;
  private static final String PRODUCT_TYPE_ORIGINAL = ContractDomainConstants.PRODUCT_TYPE_ORIGINAL;

  public static void recalculateForHistories(Set<Id> contractHistoryIds) {
    if (contractHistoryIds == null || contractHistoryIds.isEmpty()) {
      return;
    }

    Map<Id, Decimal> arrByHistoryId = new Map<Id, Decimal>();
    Map<Id, Decimal> aveArrByHistoryId = new Map<Id, Decimal>();
    calculateArrMetricsByHistoryId(
      contractHistoryIds,
      arrByHistoryId,
      aveArrByHistoryId
    );

    Map<Id, ContractHistory__c> histories = new Map<Id, ContractHistory__c>(
      [
        SELECT Id, ARR__c, AveARR__c
        FROM ContractHistory__c
        WHERE Id IN :contractHistoryIds
        WITH SYSTEM_MODE
      ]
    );

    List<ContractHistory__c> historiesToUpdate = new List<ContractHistory__c>();

    for (Id historyId : contractHistoryIds) {
      ContractHistory__c history = histories.get(historyId);
      if (history == null) {
        continue;
      }

      Decimal arr = arrByHistoryId.containsKey(historyId)
        ? arrByHistoryId.get(historyId)
        : 0;
      if (arr == null) {
        arr = 0;
      }

      Decimal aveArr = aveArrByHistoryId.containsKey(historyId)
        ? aveArrByHistoryId.get(historyId)
        : 0;
      if (aveArr == null) {
        aveArr = 0;
      }

      // null は未計算扱い。0 と同一視してスキップしない。
      Boolean arrUnchanged = history.ARR__c != null && history.ARR__c == arr;
      Boolean aveArrUnchanged =
        history.AveARR__c != null &&
        history.AveARR__c == aveArr;
      if (arrUnchanged && aveArrUnchanged) {
        continue;
      }

      historiesToUpdate.add(
        new ContractHistory__c(Id = historyId, ARR__c = arr, AveARR__c = aveArr)
      );
    }

    if (!historiesToUpdate.isEmpty()) {
      SystemContextAccess.updateRecords(historiesToUpdate);
    }
  }

  private static void calculateArrMetricsByHistoryId(
    Set<Id> contractHistoryIds,
    Map<Id, Decimal> arrByHistoryId,
    Map<Id, Decimal> aveArrByHistoryId
  ) {
    Map<Id, Date> termStartDateByHistoryId = new Map<Id, Date>();
    Map<Id, Date> termEndDateByHistoryId = new Map<Id, Date>();
    Map<Id, Decimal> avePeriodAmountByHistoryId = new Map<Id, Decimal>();

    for (ContractHistory__c history : [
      SELECT Id, CurrentTermStartDate__c, CurrentTermEndDate__c
      FROM ContractHistory__c
      WHERE Id IN :contractHistoryIds
      WITH SYSTEM_MODE
    ]) {
      arrByHistoryId.put(history.Id, 0);
      avePeriodAmountByHistoryId.put(history.Id, 0);
      termStartDateByHistoryId.put(history.Id, history.CurrentTermStartDate__c);
      termEndDateByHistoryId.put(history.Id, history.CurrentTermEndDate__c);
    }

    for (ContractProduct__c product : [
      SELECT
        ContractHistory__c,
        Amount__c,
        Quantity__c,
        UnitPrice__c,
        BillingType__c,
        Type__c,
        StartDate__c,
        Enddate__c,
        Product__r.BillingType__c,
        Product__r.IncludeInARR__c
      FROM ContractProduct__c
      WHERE
        ContractHistory__c IN :contractHistoryIds
        AND Type__c != :PRODUCT_TYPE_ORIGINAL
        AND Quantity__c > 0
      WITH SYSTEM_MODE
    ]) {
      Date termEndDate = termEndDateByHistoryId.get(product.ContractHistory__c);
      Decimal lineArr = calculateProductArr(product, termEndDate);
      Decimal currentArr = arrByHistoryId.get(product.ContractHistory__c);
      arrByHistoryId.put(product.ContractHistory__c, currentArr + lineArr);

      Decimal linePeriodAmount = calculateProductAveArrPeriodAmount(product);
      Decimal currentPeriodAmount = avePeriodAmountByHistoryId.get(
        product.ContractHistory__c
      );
      avePeriodAmountByHistoryId.put(
        product.ContractHistory__c,
        currentPeriodAmount + linePeriodAmount
      );
    }

    for (Id historyId : arrByHistoryId.keySet()) {
      Decimal periodAmountSum = avePeriodAmountByHistoryId.get(historyId);
      if (periodAmountSum == null) {
        periodAmountSum = 0;
      }

      Integer termCycles = ContractMetadataService.countMonthlyBillingCycles(
        termStartDateByHistoryId.get(historyId),
        termEndDateByHistoryId.get(historyId)
      );
      if (termCycles == null || termCycles <= 0 || periodAmountSum == 0) {
        aveArrByHistoryId.put(historyId, 0);
        continue;
      }

      aveArrByHistoryId.put(
        historyId,
        ((periodAmountSum / termCycles) * 12).setScale(2, RoundingMode.HALF_UP)
      );
    }
  }

  @TestVisible
  private static Decimal calculateProductArr(
    ContractProduct__c product,
    Date termEndDate
  ) {
    if (!isArrEligibleProduct(product)) {
      return 0;
    }

    if (termEndDate == null || product.Enddate__c != termEndDate) {
      return 0;
    }

    Decimal amount = product.Amount__c;
    if (amount == null) {
      Decimal unitPrice = product.UnitPrice__c == null
        ? 0
        : product.UnitPrice__c;
      if (unitPrice == 0) {
        return 0;
      }
      Decimal quantity = product.Quantity__c == null ? 0 : product.Quantity__c;
      return ContractMetadataService.calculateMonthlyArrRunRate(
        quantity,
        unitPrice
      );
    }
    if (amount == 0) {
      return 0;
    }

    Integer cycles = ContractMetadataService.countMonthlyBillingCycles(
      product.StartDate__c,
      product.Enddate__c
    );
    if (cycles == null || cycles <= 0) {
      return 0;
    }

    // 期間金額 ÷ 月数 × 12（ランレート）。Currency scale=2 に合わせて丸める。
    return ((amount / cycles) * 12).setScale(2, RoundingMode.HALF_UP);
  }

  /**
   * AveARR 分子用の期間金額。期末到達条件は見ない。
   * Amount null の旧データは 数量×単価×明細月数。
   */
  @TestVisible
  private static Decimal calculateProductAveArrPeriodAmount(
    ContractProduct__c product
  ) {
    if (!isArrEligibleProduct(product)) {
      return 0;
    }

    Decimal amount = product.Amount__c;
    if (amount == null) {
      Decimal unitPrice = product.UnitPrice__c == null
        ? 0
        : product.UnitPrice__c;
      Decimal quantity = product.Quantity__c == null ? 0 : product.Quantity__c;
      if (unitPrice == 0 || quantity <= 0) {
        return 0;
      }
      Integer cycles = ContractMetadataService.countMonthlyBillingCycles(
        product.StartDate__c,
        product.Enddate__c
      );
      if (cycles == null || cycles <= 0) {
        return 0;
      }
      return quantity * unitPrice * cycles;
    }
    if (amount == 0) {
      return 0;
    }
    return amount;
  }

  private static Boolean isArrEligibleProduct(ContractProduct__c product) {
    if (product == null || product.ContractHistory__c == null) {
      return false;
    }

    if (product.Type__c == PRODUCT_TYPE_ORIGINAL) {
      return false;
    }

    // 商品マスタの ARR計算対象フラグ（計算時点のマスタ値を参照）
    if (
      product.Product__r == null ||
      product.Product__r.IncludeInARR__c != true
    ) {
      return false;
    }

    String billingType = String.isNotBlank(product.BillingType__c)
      ? product.BillingType__c
      : product.Product__r.BillingType__c;
    if (billingType != BILLING_TYPE_RECURRING) {
      return false;
    }

    Decimal quantity = product.Quantity__c == null ? 0 : product.Quantity__c;
    return quantity > 0;
  }
}
