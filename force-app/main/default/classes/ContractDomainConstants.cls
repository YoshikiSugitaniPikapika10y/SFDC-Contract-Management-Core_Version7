/**
 * Shared domain string/integer constants for contract estimate/order/invoice flows.
 * Prefer these over re-declaring the same literals in each class.
 */
public without sharing class ContractDomainConstants {
  public static final String HISTORY_STATUS_ESTIMATE = 'Estimate';
  public static final String HISTORY_STATUS_ARCHIVE = 'Archive';
  public static final String HISTORY_STATUS_ORDERED = 'Ordered';

  /** StatusPath__c（表示用）。Ordered 以降の請求進捗。 */
  public static final String STATUS_PATH_INVOICING = 'Invoicing';
  public static final String STATUS_PATH_INVOICED = 'Invoiced';
  public static final String STATUS_PATH_PAID = 'Paid';

  public static final String HISTORY_TYPE_NEW = 'New';
  public static final String HISTORY_TYPE_CHANGE = 'Change';
  public static final String HISTORY_TYPE_RENEW = 'Renew';
  public static final String HISTORY_TYPE_CANCEL = 'Cancel';
  public static final String HISTORY_TYPE_ADD = 'Add';

  public static final String LIFECYCLE_TERM = 'Term';
  public static final String LIFECYCLE_SPOT = 'Spot';

  public static final String BILLING_TYPE_RECURRING = '継続課金';
  public static final String BILLING_TYPE_ONE_TIME = '一回課金';
  public static final String MONTHLY_BILLING_CYCLE = '月';

  public static final String PRODUCT_TYPE_ORIGINAL = 'Original';
  public static final String PRODUCT_TYPE_REMAKE = 'Remake';
  public static final String LEGACY_PRODUCT_TYPE_DERIVATIVE = 'derivative';
  public static final String PRODUCT_TYPE_NEW = 'New';
  public static final String PRODUCT_TYPE_RENEW = 'Renew';

  public static final Integer NOTE_MAX_LENGTH = ContractHistory__c.Note__c.getDescribe()
    .getLength();
}
