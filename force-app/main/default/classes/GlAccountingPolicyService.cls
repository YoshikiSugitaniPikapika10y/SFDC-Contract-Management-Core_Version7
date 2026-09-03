public without sharing class GlAccountingPolicyService {
  public static final String ORG_DEFAULT_NAME = 'OrgDefault';
  public static Boolean allowFreezeWrite;

  public class PolicyException extends Exception {
  }

  private static Boolean cachedHasTerminalInvoice;

  /** 仕様: Accounting 第3.1節、Core 第11.8節 */
  public static Boolean hasTerminalInvoice() {
    if (cachedHasTerminalInvoice != null) {
      return cachedHasTerminalInvoice;
    }
    cachedHasTerminalInvoice = [
        SELECT COUNT()
        FROM Invoice__c
        WHERE InvoiceTransactionStatus__c IN ('Confirmed', 'Cancelled')
        WITH SYSTEM_MODE
        LIMIT 1
      ] > 0;
    return cachedHasTerminalInvoice;
  }

  /** 仕様: Accounting 第3.1節、Core 第11.8節 */
  public static Boolean isPolicyLocked(GlAccountingPolicy__c policy) {
    return (policy != null && policy.FrozenAt__c != null) || hasTerminalInvoice();
  }

  private static GlAccountingPolicy__c cachedOrgPolicy;

  /** 仕様: Accounting 第3.1節。削除後に0件判定へ残さない。 */
  public static void clearCachedOrgPolicy() {
    cachedOrgPolicy = null;
    cachedHasTerminalInvoice = null;
  }

  /** 仕様: Accounting 第3.1節 */
  public static GlAccountingPolicy__c requireOrgPolicy() {
    if (cachedOrgPolicy != null) {
      return cachedOrgPolicy;
    }
    List<GlAccountingPolicy__c> rows = [
      SELECT
        Id,
        Name,
        AccountingEnabled__c,
        RevenueRecognitionBasis__c,
        TaxRecognitionTiming__c,
        MonthlyBucketMethod__c,
        MonthlyRecognitionDatePosition__c,
        RoundingTargetBucket__c,
        FrozenAt__c,
        FrozenBy__c
      FROM GlAccountingPolicy__c
      WITH SYSTEM_MODE
      LIMIT 2
    ];
    if (rows.isEmpty()) {
      throw new PolicyException('Accounting会計方針がありません。');
    }
    if (rows.size() > 1) {
      throw new PolicyException('Accounting会計方針は組織内1件だけです。');
    }
    cachedOrgPolicy = rows[0];
    return cachedOrgPolicy;
  }

  /** 仕様: Accounting 第3.1節 */
  public static GlAccountingPolicy__c freezeOnFirstConfirm() {
    List<GlAccountingPolicy__c> rows = [
      SELECT
        Id,
        Name,
        AccountingEnabled__c,
        RevenueRecognitionBasis__c,
        TaxRecognitionTiming__c,
        MonthlyBucketMethod__c,
        MonthlyRecognitionDatePosition__c,
        RoundingTargetBucket__c,
        FrozenAt__c,
        FrozenBy__c
      FROM GlAccountingPolicy__c
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    if (rows.isEmpty()) {
      throw new PolicyException('Accounting会計方針がありません。');
    }
    if (rows.size() > 1) {
      throw new PolicyException('Accounting会計方針は組織内1件だけです。');
    }
    GlAccountingPolicy__c policy = rows[0];
    // 仕様: 第5.7節。固定時に許可集合を検証する。
    deriveAllowedPatternKeys(policy);
    if (policy.FrozenAt__c != null) {
      cachedOrgPolicy = policy;
      return policy;
    }
    Boolean previous = allowFreezeWrite;
    allowFreezeWrite = true;
    try {
      policy.FrozenAt__c = System.now();
      policy.FrozenBy__c = UserInfo.getUserId();
      update policy;
    } finally {
      allowFreezeWrite = previous;
    }
    cachedOrgPolicy = policy;
    return policy;
  }

  /** 仕様: Accounting 第5.6節、第5.7節。保存・固定・原因操作から呼ぶ。 */
  public static Set<String> deriveAllowedPatternKeys(GlAccountingPolicy__c policy) {
    if (policy == null) {
      throw new PolicyException('Accounting会計方針がありません。');
    }
    String basis = policy.RevenueRecognitionBasis__c;
    String tax = policy.TaxRecognitionTiming__c;
    if (basis != 'BillingBasis' && basis != 'CashBasis') {
      throw new PolicyException('売上計上方針が不正です。');
    }
    if (tax != 'AtInvoice' && tax != 'AtRecognition') {
      throw new PolicyException('税認識方針が不正です。');
    }
    Set<String> keys = new Set<String>();
    if (basis == 'BillingBasis' && tax == 'AtInvoice') {
      keys.add('BILLING_BASIS_INVOICE_BODY');
      keys.add('BILLING_TAX_AT_INVOICE');
      keys.add('BILLING_BASIS_REVENUE_BODY');
    } else if (basis == 'BillingBasis' && tax == 'AtRecognition') {
      keys.add('BILLING_BASIS_INVOICE_BODY');
      keys.add('BILLING_BASIS_INVOICE_TAX_DEFERRED');
      keys.add('BILLING_BASIS_REVENUE_BODY');
      keys.add('BILLING_BASIS_REVENUE_TAX');
    } else if (basis == 'CashBasis' && tax == 'AtInvoice') {
      keys.add('CASH_BASIS_INVOICE_BODY_CTA_TRANSFER');
      keys.add('BILLING_TAX_AT_INVOICE');
      keys.add('CASH_BASIS_REVENUE_BODY');
    } else {
      keys.add('CASH_BASIS_INVOICE_BODY_CTA_TRANSFER');
      keys.add('CASH_BASIS_INVOICE_TAX_CTA_TRANSFER');
      keys.add('CASH_BASIS_REVENUE_BODY');
      keys.add('CASH_BASIS_REVENUE_TAX');
    }
    keys.add('PAYMENT_INVOICE_CURRENT');
    keys.add('PAYMENT_NON_INVOICE_POSITIVE');
    keys.add('PAYMENT_NON_INVOICE_NEGATIVE');
    keys.add('PAYMENT_INVOICE_HISTORICAL_POSITIVE_CASH');
    keys.add('PAYMENT_INVOICE_HISTORICAL_NEGATIVE_CASH');
    keys.add('PAYMENT_INVOICE_HISTORICAL_UAC_TRANSFER');
    keys.add('PAYMENT_INVOICE_HISTORICAL_SP_TRANSFER');
    assertAllowedPatternSet(keys, basis, tax);
    return keys;
  }

  /** 仕様: Accounting 第5.7節 */
  private static void assertAllowedPatternSet(
    Set<String> keys,
    String basis,
    String tax
  ) {
    Boolean bodyInvoiceBilling = keys.contains('BILLING_BASIS_INVOICE_BODY');
    Boolean bodyInvoiceCash = keys.contains('CASH_BASIS_INVOICE_BODY_CTA_TRANSFER');
    if (bodyInvoiceBilling == bodyInvoiceCash) {
      throw new PolicyException('BODY_INVOICEの許可パターンが1件ではありません。');
    }
    Boolean bodyRevenueBilling = keys.contains('BILLING_BASIS_REVENUE_BODY');
    Boolean bodyRevenueCash = keys.contains('CASH_BASIS_REVENUE_BODY');
    if (bodyRevenueBilling == bodyRevenueCash) {
      throw new PolicyException('BODY_REVENUEの許可パターンが1件ではありません。');
    }
    if (basis == 'BillingBasis' && !(bodyInvoiceBilling && bodyRevenueBilling)) {
      throw new PolicyException('請求基準の本体パターンの対が不正です。');
    }
    if (basis == 'CashBasis' && !(bodyInvoiceCash && bodyRevenueCash)) {
      throw new PolicyException('入金連動前受基準の本体パターンの対が不正です。');
    }
    Boolean taxAtInvoice = keys.contains('BILLING_TAX_AT_INVOICE');
    Boolean taxDeferredBilling = keys.contains('BILLING_BASIS_INVOICE_TAX_DEFERRED');
    Boolean taxRevenueBilling = keys.contains('BILLING_BASIS_REVENUE_TAX');
    Boolean taxCtaCash = keys.contains('CASH_BASIS_INVOICE_TAX_CTA_TRANSFER');
    Boolean taxRevenueCash = keys.contains('CASH_BASIS_REVENUE_TAX');
    if (tax == 'AtInvoice') {
      if (!taxAtInvoice || taxDeferredBilling || taxRevenueBilling || taxCtaCash || taxRevenueCash) {
        throw new PolicyException('請求時税の許可パターンが不正です。');
      }
    } else if (basis == 'BillingBasis') {
      if (!taxDeferredBilling || !taxRevenueBilling || taxAtInvoice || taxCtaCash || taxRevenueCash) {
        throw new PolicyException('請求基準・売上計上時税の許可パターンが不正です。');
      }
    } else {
      if (!taxCtaCash || !taxRevenueCash || taxAtInvoice || taxDeferredBilling || taxRevenueBilling) {
        throw new PolicyException('入金連動前受基準・売上計上時税の許可パターンが不正です。');
      }
    }
  }

  /** 仕様: Accounting 第3.2節。未固定の月次方式変更で組織内の請求明細を書き直す。 */
  public static void rewriteRecognitionBucketCounts() {
    List<InvoiceLine__c> lines = [
      SELECT
        Id,
        ServicePeriodStartDate__c,
        ServicePeriodEndDate__c,
        RevenueRecognitionBasis__c,
        RecognitionBucketCount__c
      FROM InvoiceLine__c
      WITH SYSTEM_MODE
    ];
    InvoiceCanonicalService.applyRecognitionBucketCount(lines);
    if (!lines.isEmpty()) {
      update lines;
    }
  }

  /** 仕様: Accounting 第13.5節 */
  public static GlAccountingPolicy__c newOrgDefault() {
    return new GlAccountingPolicy__c(
      Name = ORG_DEFAULT_NAME,
      AccountingEnabled__c = false,
      RevenueRecognitionBasis__c = 'BillingBasis',
      TaxRecognitionTiming__c = 'AtInvoice',
      MonthlyBucketMethod__c = 'Auto',
      MonthlyRecognitionDatePosition__c = 'BucketEnd',
      RoundingTargetBucket__c = 'Last'
    );
  }
}
