/**
 * 契約商品の符号付き金額計算（画面 Step3 表示用と同定義）。
 * 永続化時は EstimateSaveService が画面確認値をそのまま保存し、本クラスで上書きしない。
 * Original（前回条件の打消し行）は符号を反転する。課金形態に応じた期間按分は
 * ContractMetadataService 側の定義に従う。
 */
public without sharing class ContractProductAmountUtil {
  private static final String PRODUCT_TYPE_ORIGINAL = ContractDomainConstants.PRODUCT_TYPE_ORIGINAL;

  public static Decimal calculateSignedAmount(
    ContractProduct__c product,
    String productBillingType
  ) {
    if (product == null) {
      return null;
    }
    Decimal unsignedAmount = calculateUnsignedAmount(
      product.Quantity__c,
      product.UnitPrice__c,
      resolveBillingType(product, productBillingType),
      product.StartDate__c,
      product.Enddate__c
    );
    return applyProductTypeSign(unsignedAmount, product);
  }

  private static Decimal applyProductTypeSign(
    Decimal amount,
    ContractProduct__c product
  ) {
    if (amount == null || product == null) {
      return amount;
    }
    // Original = 前回条件の打消し行（計算額の符号反転）。値引き（負単価）も正になる。
    // Remake は Type だけで判定し、Amount 符号からの推測はしない。
    if (product.Type__c == PRODUCT_TYPE_ORIGINAL) {
      return -amount;
    }
    return amount;
  }

  public static Decimal calculateUnsignedAmount(
    Decimal quantity,
    Decimal unitPrice,
    String billingType,
    Date startDate,
    Date endDate
  ) {
    Decimal qty = quantity == null ? 0 : quantity;
    Decimal price = unitPrice == null ? 0 : unitPrice;
    if (qty <= 0 || price == 0) {
      return 0;
    }

    if (!ContractMetadataService.isRecurringBillingType(billingType)) {
      return (qty * price).setScale(0, RoundingMode.HALF_UP);
    }
    if (startDate == null || endDate == null) {
      return null;
    }

    Integer cycles = MonthlyBillingPeriodUtil.countMonthlyCycles(
      startDate,
      endDate
    );
    if (cycles == null || cycles < 1) {
      return null;
    }
    return (qty * price * cycles).setScale(0, RoundingMode.HALF_UP);
  }

  public static Decimal applyProductTypeSign(
    Decimal amount,
    String productType
  ) {
    if (amount == null) {
      return null;
    }
    if (productType == PRODUCT_TYPE_ORIGINAL) {
      return -amount;
    }
    return amount;
  }

  private static String resolveBillingType(
    ContractProduct__c product,
    String productBillingType
  ) {
    if (product != null && String.isNotBlank(product.BillingType__c)) {
      return product.BillingType__c;
    }
    return productBillingType;
  }
}
