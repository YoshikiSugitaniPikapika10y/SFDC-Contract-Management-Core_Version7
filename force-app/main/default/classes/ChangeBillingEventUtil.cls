/**
 * Change の Original/Remake 系統で「課金イベント」があるかを判定する。
 *
 * Apex（本クラス・EstimateCreateController）と LWC（estimateLineItemUtils）で
 * 同じ定義を共有する前提: 数量・単価等の内容差・途中開始・終了日延長。
 * 請求設定の差は課金イベントに含めない（Core 第4.4.1節）。
 * 片側だけ変更すると見積書表示と保存バリデーションがずれる。
 */
public without sharing class ChangeBillingEventUtil {
  private static final String PRODUCT_TYPE_ORIGINAL = ContractDomainConstants.PRODUCT_TYPE_ORIGINAL;
  private static final String PRODUCT_TYPE_REMAKE = ContractDomainConstants.PRODUCT_TYPE_REMAKE;
  private static final String PRODUCT_TYPE_DERIVATIVE = ContractDomainConstants.LEGACY_PRODUCT_TYPE_DERIVATIVE;
  private static final String HISTORY_TYPE_CHANGE = ContractDomainConstants.HISTORY_TYPE_CHANGE;

  /**
   * 見積書向け: Change で課金イベントのない Original/Remake 系統を除外する。
   * New/Renew など他 Type、および課金イベントがある系統は残す。
   */
  public static List<ContractProduct__c> filterProductsForEstimateDocument(
    String historyType,
    List<ContractProduct__c> products
  ) {
    if (products == null || products.isEmpty()) {
      return new List<ContractProduct__c>();
    }
    if (historyType != HISTORY_TYPE_CHANGE) {
      return products;
    }

    Map<Id, ContractProduct__c> originalByLineageId = new Map<Id, ContractProduct__c>();
    Map<Id, List<ContractProduct__c>> remakesByLineageId = new Map<Id, List<ContractProduct__c>>();

    for (ContractProduct__c product : products) {
      if (product == null || product.PreviousContractProduct__c == null) {
        continue;
      }
      Id lineageId = product.PreviousContractProduct__c;
      if (isOriginalType(product.Type__c)) {
        originalByLineageId.put(lineageId, product);
      } else if (isRemakeType(product.Type__c)) {
        if (!remakesByLineageId.containsKey(lineageId)) {
          remakesByLineageId.put(lineageId, new List<ContractProduct__c>());
        }
        remakesByLineageId.get(lineageId).add(product);
      }
    }

    Set<Id> excludedIds = new Set<Id>();
    for (Id lineageId : remakesByLineageId.keySet()) {
      ContractProduct__c original = originalByLineageId.get(lineageId);
      List<ContractProduct__c> remakes = remakesByLineageId.get(lineageId);
      if (original == null || remakes == null || remakes.isEmpty()) {
        continue;
      }
      if (!lineageHasBillingEvent(original, remakes)) {
        excludedIds.add(original.Id);
        for (ContractProduct__c remake : remakes) {
          if (remake.Id != null) {
            excludedIds.add(remake.Id);
          }
        }
      }
    }

    if (excludedIds.isEmpty()) {
      return products;
    }

    List<ContractProduct__c> filtered = new List<ContractProduct__c>();
    for (ContractProduct__c product : products) {
      if (
        product != null &&
        product.Id != null &&
        excludedIds.contains(product.Id)
      ) {
        continue;
      }
      filtered.add(product);
    }
    return filtered;
  }

  public static Boolean lineageHasBillingEvent(
    ContractProduct__c original,
    List<ContractProduct__c> remakes
  ) {
    if (original == null || remakes == null || remakes.isEmpty()) {
      return false;
    }

    List<ContractProduct__c> datedRemakes = new List<ContractProduct__c>();
    for (ContractProduct__c remake : remakes) {
      if (remake != null && remake.StartDate__c != null) {
        datedRemakes.add(remake);
      }
    }
    if (datedRemakes.isEmpty()) {
      return false;
    }
    datedRemakes.sort(new ContractProductStartDateComparator());

    ContractProduct__c first = datedRemakes[0];
    if (
      original.StartDate__c != null &&
      first.StartDate__c != null &&
      first.StartDate__c > original.StartDate__c
    ) {
      return true;
    }

    for (ContractProduct__c remake : datedRemakes) {
      if (doesBillingContentDiffer(remake, original)) {
        return true;
      }
      // 終了日延長のみ（内容同一）も課金イベント。見積書明細から落ちないようにする。
      if (
        remake.Enddate__c != null &&
        original.Enddate__c != null &&
        remake.Enddate__c > original.Enddate__c
      ) {
        return true;
      }
    }
    return false;
  }

  /**
   * 仕様: Core 第4.4.1節
   * 継続課金イベントの内容差は数量・単価等。請求設定の差は含めない。
   */
  public static Boolean doesBillingContentDiffer(
    ContractProduct__c remake,
    ContractProduct__c original
  ) {
    return doesNonInvoiceSettingBillingContentDiffer(remake, original);
  }

  /**
   * Change の課金イベントが請求設定の差だけか。
   * 受注時に拒否する（金額不変のため請求スケジュールが切り替わらず、未請求なら差し戻し編集が正）。
   */
  public static Boolean isInvoiceSettingOnlyChange(
    List<ContractProduct__c> products
  ) {
    if (products == null || products.isEmpty()) {
      return false;
    }

    Map<Id, ContractProduct__c> originalByLineageId = new Map<Id, ContractProduct__c>();
    Map<Id, List<ContractProduct__c>> remakesByLineageId = new Map<Id, List<ContractProduct__c>>();
    Boolean sawInvoiceSettingDiff = false;

    for (ContractProduct__c product : products) {
      if (product == null) {
        continue;
      }
      if (!isOriginalType(product.Type__c) && !isRemakeType(product.Type__c)) {
        // Type=New 等の追加行があれば設定だけの Change ではない
        if (
          product.Product__c != null &&
          product.Quantity__c != null &&
          product.Quantity__c > 0
        ) {
          return false;
        }
        continue;
      }
      if (product.PreviousContractProduct__c == null) {
        continue;
      }
      Id lineageId = product.PreviousContractProduct__c;
      if (isOriginalType(product.Type__c)) {
        originalByLineageId.put(lineageId, product);
      } else if (isRemakeType(product.Type__c)) {
        if (!remakesByLineageId.containsKey(lineageId)) {
          remakesByLineageId.put(lineageId, new List<ContractProduct__c>());
        }
        remakesByLineageId.get(lineageId).add(product);
      }
    }

    for (Id lineageId : remakesByLineageId.keySet()) {
      ContractProduct__c original = originalByLineageId.get(lineageId);
      List<ContractProduct__c> remakes = remakesByLineageId.get(lineageId);
      if (original == null || remakes == null || remakes.isEmpty()) {
        continue;
      }

      List<ContractProduct__c> datedRemakes = new List<ContractProduct__c>();
      for (ContractProduct__c remake : remakes) {
        if (remake != null && remake.StartDate__c != null) {
          datedRemakes.add(remake);
        }
      }
      if (datedRemakes.isEmpty()) {
        continue;
      }
      datedRemakes.sort(new ContractProductStartDateComparator());

      ContractProduct__c first = datedRemakes[0];
      if (
        original.StartDate__c != null &&
        first.StartDate__c != null &&
        first.StartDate__c > original.StartDate__c
      ) {
        return false;
      }

      for (ContractProduct__c remake : datedRemakes) {
        if (doesNonInvoiceSettingBillingContentDiffer(remake, original)) {
          return false;
        }
        if (
          remake.Enddate__c != null &&
          original.Enddate__c != null &&
          remake.Enddate__c > original.Enddate__c
        ) {
          return false;
        }
        if (doesInvoiceSettingDiffer(remake, original)) {
          sawInvoiceSettingDiff = true;
        }
      }
    }

    return sawInvoiceSettingDiff;
  }

  @TestVisible
  private static Boolean doesNonInvoiceSettingBillingContentDiffer(
    ContractProduct__c remake,
    ContractProduct__c original
  ) {
    if (remake == null || original == null) {
      return false;
    }
    if (remake.Product__c != original.Product__c) {
      return true;
    }
    if (!decimalsEqual(remake.Quantity__c, original.Quantity__c)) {
      return true;
    }
    if (!decimalsEqual(remake.UnitPrice__c, original.UnitPrice__c)) {
      return true;
    }
    String leftBillingType = remake.BillingType__c == null
      ? ''
      : remake.BillingType__c;
    String rightBillingType = original.BillingType__c == null
      ? ''
      : original.BillingType__c;
    return leftBillingType != rightBillingType;
  }

  private static Boolean doesInvoiceSettingDiffer(
    ContractProduct__c remake,
    ContractProduct__c original
  ) {
    if (remake == null || original == null) {
      return false;
    }
    String leftInvoice = remake.InvoiceSetting__c == null
      ? ''
      : remake.InvoiceSetting__c;
    String rightInvoice = original.InvoiceSetting__c == null
      ? ''
      : original.InvoiceSetting__c;
    return leftInvoice != rightInvoice;
  }

  private static Boolean isOriginalType(String productType) {
    return productType == PRODUCT_TYPE_ORIGINAL;
  }

  private static Boolean isRemakeType(String productType) {
    return productType == PRODUCT_TYPE_REMAKE ||
      productType == PRODUCT_TYPE_DERIVATIVE;
  }

  private static Boolean decimalsEqual(Decimal left, Decimal right) {
    if (left == null && right == null) {
      return true;
    }
    if (left == null || right == null) {
      return false;
    }
    return left == right;
  }

  private class ContractProductStartDateComparator implements Comparator<ContractProduct__c> {
    public Integer compare(ContractProduct__c left, ContractProduct__c right) {
      if (left == null && right == null) {
        return 0;
      }
      if (left == null) {
        return 1;
      }
      if (right == null) {
        return -1;
      }
      if (left.StartDate__c == right.StartDate__c) {
        return 0;
      }
      if (left.StartDate__c == null) {
        return 1;
      }
      if (right.StartDate__c == null) {
        return -1;
      }
      return left.StartDate__c < right.StartDate__c ? -1 : 1;
    }
  }
}
