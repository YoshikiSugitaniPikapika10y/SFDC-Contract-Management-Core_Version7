/**
 * 請求アカウント／請求書の届け方。組織3択は能力、届け方は相手のマスタ。
 */
public without sharing class InvoiceDeliveryMethodService {
  public static final String EMAIL = 'Email';
  public static final String POST = 'Post';
  public static final String NONE = 'None';
  public static final String REQUIRED_ON_BILLING_ACCOUNT_MESSAGE =
    '組織の請求書設定がPDFとメール送付のとき、届け方は必須です。';
  public static final String REQUIRED_ON_CONFIRM_MESSAGE =
    '組織の請求書設定がPDFとメール送付のとき、届け方が空の請求は確定できません。';
  public static final String SEND_NOT_ALLOWED_MESSAGE =
    '届け方がメールのときだけ送付できます。';

  public class DeliveryMethodException extends Exception {
  }

  /** 仕様: Core 第3.3.7節。組織が PdfAndEmail のときだけ空を拒否する。空をメールとみなさない。 */
  public static void assertRequiredOnBillingAccount(
    List<BillingAccount__c> records
  ) {
    if (records == null || !orgRequiresDeliveryMethod()) {
      return;
    }
    for (BillingAccount__c record : records) {
      if (record == null) {
        continue;
      }
      if (String.isBlank(record.InvoiceDeliveryMethod__c)) {
        record.addError(REQUIRED_ON_BILLING_ACCOUNT_MESSAGE);
      }
    }
  }

  /** 仕様: Core 第7.9.1節。組織が PdfAndEmail のとき、確定する請求のスナップショット空を拒否する。 */
  public static void assertRequiredOnConfirm(Invoice__c invoice) {
    if (!orgRequiresDeliveryMethod()) {
      return;
    }
    if (invoice == null || String.isBlank(invoice.InvoiceDeliveryMethodSnapShot__c)) {
      throw new DeliveryMethodException(REQUIRED_ON_CONFIRM_MESSAGE);
    }
  }

  /** 仕様: Core 第7.10節。組織が PdfAndEmail かつスナップショットが Email のときだけ送付可。空はメールではない。 */
  public static Boolean allowsEmailSend(Invoice__c invoice) {
    if (invoice == null) {
      return false;
    }
    if (!orgIsPdfAndEmail()) {
      return false;
    }
    return invoice.InvoiceDeliveryMethodSnapShot__c == EMAIL;
  }

  private static Boolean orgRequiresDeliveryMethod() {
    return orgIsPdfAndEmail();
  }

  private static Boolean orgIsPdfAndEmail() {
    try {
      return ContractDocumentSettingService.requireSendMode('Invoice') ==
        ContractDocumentSettingService.MODE_PDF_AND_EMAIL;
    } catch (Exception ex) {
      return false;
    }
  }
}
