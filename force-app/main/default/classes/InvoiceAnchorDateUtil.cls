/**
 * 契約商品の請求基準日・請求回数（月次分割）を決定する。
 * 見積保存時にセットし、請求商品生成では保存値を請求先設定でスナップするだけ。
 */
public without sharing class InvoiceAnchorDateUtil {
  public class ResolvedAnchor {
    public Date anchorDate;
    public Integer billingCycleCount;
  }

  public static ResolvedAnchor resolve(
    String historyType,
    Date effectiveDate,
    ContractProduct__c product
  ) {
    ResolvedAnchor result = new ResolvedAnchor();
    if (product == null) {
      return result;
    }

    String invoiceSetting = ContractMetadataService.normalizeInvoiceSettingLabel(
      product.InvoiceSetting__c
    );
    if (String.isBlank(invoiceSetting)) {
      return result;
    }

    Date startDate = product.StartDate__c;
    Date endDate = product.Enddate__c;
    if (startDate == null) {
      return result;
    }

    ContractMetadataService.InvoiceDateRouteType route = ContractMetadataService.resolveInvoiceDateRoute(
      invoiceSetting
    );

    if (
      route ==
      ContractMetadataService.InvoiceDateRouteType.BULK_CONTRACT_END_PLUS_ONE
    ) {
      if (endDate == null) {
        return result;
      }
      result.anchorDate = endDate.addDays(1);
      return result;
    }

    if (
      route == ContractMetadataService.InvoiceDateRouteType.MONTHLY_PERIOD_START
    ) {
      if (endDate == null) {
        return result;
      }
      Integer cycles = MonthlyBillingPeriodUtil.countMonthlyCycles(
        startDate,
        endDate
      );
      result.anchorDate = startDate;
      if (cycles != null && cycles > 0) {
        result.billingCycleCount = cycles;
      }
      return result;
    }

    result.anchorDate = startDate;
    if (
      historyType == ContractDomainConstants.HISTORY_TYPE_CHANGE &&
      effectiveDate != null &&
      product.Type__c != ContractDomainConstants.PRODUCT_TYPE_NEW
    ) {
      result.anchorDate = effectiveDate;
    }
    return result;
  }

  public static void applyToContractProduct(
    ContractProduct__c product,
    String historyType,
    Date effectiveDate
  ) {
    if (product == null) {
      return;
    }
    ResolvedAnchor resolved = resolve(historyType, effectiveDate, product);
    product.InvoiceAnchorDate__c = resolved.anchorDate;
    product.InvoiceBillingCycleCount__c = resolved.billingCycleCount;
  }
}
