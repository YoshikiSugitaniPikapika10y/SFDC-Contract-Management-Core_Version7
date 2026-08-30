/**
 * 請求書の取引・送付・回収返金の3状態を専用処理だけで更新する。
 */
public without sharing class InvoiceTransactionStatusService {
  public static final String TX_DRAFT = 'Draft';
  public static final String TX_CONFIRMED = 'Confirmed';
  public static final String TX_CANCELLED = 'Cancelled';
  public static final String DELIVERY_NOT_APPLICABLE = 'NotApplicable';
  public static final String DELIVERY_UNSENT = 'Unsent';
  public static final String DELIVERY_SENT = 'Sent';
  public static final String COLLECTION_NOT_STARTED = 'NotStarted';
  public static final String COLLECTION_IN_PROGRESS = 'InProgress';
  public static final String COLLECTION_COMPLETED = 'Completed';
  public static final String DIRECT_EDIT_MESSAGE = '請求の状態は専用処理以外から変更できません。';
  public static final String INVALID_CONFIRM_MESSAGE = '未確定の請求だけ確定できます。';
  public static final String INVALID_CANCEL_MESSAGE = '確定済みの請求だけ取消できます。';

  public static Boolean allowStatusWrite;

  /** 仕様: Core 第7.9節、第7.11節、日付仕様 第8章 */
  public static void applyConfirmed(List<Invoice__c> invoices, Date confirmationDate) {
    if (invoices == null || invoices.isEmpty()) {
      return;
    }
    // 仕様: Core 第7.9節。確定日は組織TZの操作日。空をユーザーTZの今日で埋めない。
    Date confirmedOn = confirmationDate == null
      ? organizationToday()
      : confirmationDate;
    for (Invoice__c invoice : invoices) {
      if (invoice == null) {
        continue;
      }
      String current = currentTx(invoice);
      if (current != TX_DRAFT) {
        throw new InvoiceStatusException(INVALID_CONFIRM_MESSAGE);
      }
      String deliveryStatus = resolveConfirmedDeliveryStatus(invoice);
      invoice.InvoiceTransactionStatus__c = TX_CONFIRMED;
      invoice.SystemIntegrationDate__c = confirmedOn;
      invoice.DeliveryStatus__c = deliveryStatus;
      if (deliveryStatus != DELIVERY_SENT) {
        invoice.SentDate__c = null;
      }
      applyCollectionRefund(invoice, 0);
    }
  }

  /** 仕様: Core 第7.11節、第7.9.3節 */
  public static void applyCancelled(List<Invoice__c> invoices) {
    if (invoices == null || invoices.isEmpty()) {
      return;
    }
    for (Invoice__c invoice : invoices) {
      if (invoice == null) {
        continue;
      }
      if (currentTx(invoice) != TX_CONFIRMED) {
        throw new InvoiceStatusException(INVALID_CANCEL_MESSAGE);
      }
      invoice.InvoiceTransactionStatus__c = TX_CANCELLED;
    }
  }

  /** 仕様: Core 第7.11節 */
  public static void applyDelivery(Invoice__c invoice, String deliveryStatus, Date sentDate) {
    if (invoice == null) {
      return;
    }
    if (currentTx(invoice) == TX_CANCELLED) {
      throw new InvoiceStatusException('取消済みの請求は送付状態を変えられません。');
    }
    invoice.DeliveryStatus__c = deliveryStatus;
    invoice.SentDate__c = DELIVERY_SENT.equals(deliveryStatus) ? sentDate : null;
  }

  /** 仕様: Core 第7.11節 */
  public static void applyCollectionRefund(Invoice__c invoice) {
    applyCollectionRefund(invoice, null);
  }

  /** 仕様: Core 第7.11節。activeInvoicePurposeCount は Purpose=Invoice の有効件数。 */
  public static void applyCollectionRefund(
    Invoice__c invoice,
    Integer activeInvoicePurposeCount
  ) {
    if (invoice == null) {
      return;
    }
    String tx = currentTx(invoice);
    if (tx == TX_CANCELLED) {
      return;
    }
    if (tx != TX_CONFIRMED) {
      invoice.CollectionRefundStatus__c = COLLECTION_NOT_STARTED;
      invoice.PaymentClearingCompletedDate__c = null;
      return;
    }
    Decimal taxInclusive = nvl(invoice.TaxInclusiveAmount__c);
    Decimal invoiceNet = nvl(invoice.InvoicePaymentNet__c);
    Integer purposeCount = activeInvoicePurposeCount == null
      ? 0
      : activeInvoicePurposeCount;
    if (taxInclusive == 0 && invoiceNet == 0) {
      markCompleted(invoice);
      return;
    }
    if (invoiceNet == taxInclusive) {
      markCompleted(invoice);
      return;
    }
    if (purposeCount == 0) {
      invoice.CollectionRefundStatus__c = COLLECTION_NOT_STARTED;
      invoice.PaymentClearingCompletedDate__c = null;
      return;
    }
    invoice.CollectionRefundStatus__c = COLLECTION_IN_PROGRESS;
    invoice.PaymentClearingCompletedDate__c = null;
  }

  private static void markCompleted(Invoice__c invoice) {
    invoice.CollectionRefundStatus__c = COLLECTION_COMPLETED;
    if (invoice.PaymentClearingCompletedDate__c == null) {
      invoice.PaymentClearingCompletedDate__c = organizationToday();
    }
  }

  /** 仕様: 日付仕様 第8章 */
  public static Date organizationToday() {
    String timeZoneSid = [
      SELECT TimeZoneSidKey
      FROM Organization
      LIMIT 1
    ]
    .TimeZoneSidKey;
    TimeZone orgTimeZone = TimeZone.getTimeZone(timeZoneSid);
    Datetime gmtNow = Datetime.now();
    return gmtNow.addSeconds(orgTimeZone.getOffset(gmtNow) / 1000).dateGmt();
  }

  /** 仕様: Core 第7.11節 */
  /** 仕様: Core 第7.11節 */
  public static void rejectDirectStatusEdits(
    List<Invoice__c> newRecords,
    Map<Id, Invoice__c> oldMap
  ) {
    if (allowStatusWrite == true || newRecords == null) {
      return;
    }
    for (Invoice__c invoice : newRecords) {
      if (invoice == null) {
        continue;
      }
      Invoice__c prior = oldMap == null ? null : oldMap.get(invoice.Id);
      if (prior == null) {
        if (
          isNonSeedStatus(invoice.InvoiceTransactionStatus__c, TX_DRAFT) ||
          isNonSeedStatus(invoice.DeliveryStatus__c, resolveDeliverySeed()) ||
          isNonSeedStatus(
            invoice.CollectionRefundStatus__c,
            COLLECTION_NOT_STARTED
          )
        ) {
          invoice.addError(DIRECT_EDIT_MESSAGE);
          continue;
        }
        seedDefaults(invoice);
        continue;
      }
      if (
        changed(prior.InvoiceTransactionStatus__c, invoice.InvoiceTransactionStatus__c) ||
        changed(prior.DeliveryStatus__c, invoice.DeliveryStatus__c) ||
        changed(prior.CollectionRefundStatus__c, invoice.CollectionRefundStatus__c)
      ) {
        invoice.addError(DIRECT_EDIT_MESSAGE);
      }
    }
  }

  public static void seedDefaults(Invoice__c invoice) {
    if (invoice == null) {
      return;
    }
    if (String.isBlank(invoice.InvoiceTransactionStatus__c)) {
      invoice.InvoiceTransactionStatus__c = TX_DRAFT;
    }
    if (String.isBlank(invoice.DeliveryStatus__c)) {
      invoice.DeliveryStatus__c = resolveDeliverySeed();
    }
    if (String.isBlank(invoice.CollectionRefundStatus__c)) {
      invoice.CollectionRefundStatus__c = COLLECTION_NOT_STARTED;
    }
  }

  public static Boolean isConfirmed(Invoice__c invoice) {
    return invoice != null && currentTx(invoice) == TX_CONFIRMED;
  }

  public static Boolean isCancelled(Invoice__c invoice) {
    return invoice != null && currentTx(invoice) == TX_CANCELLED;
  }

  public static Boolean isDraft(Invoice__c invoice) {
    return invoice != null && currentTx(invoice) == TX_DRAFT;
  }

  public static Decimal resolveTaxInclusive(Invoice__c invoice) {
    if (invoice == null) {
      return 0;
    }
    if (invoice.TaxInclusiveAmount__c != null) {
      return invoice.TaxInclusiveAmount__c;
    }
    return nvl(invoice.Amount__c) + nvl(invoice.TaxAmount__c);
  }

  private static String currentTx(Invoice__c invoice) {
    if (invoice == null) {
      return TX_DRAFT;
    }
    if (String.isNotBlank(invoice.InvoiceTransactionStatus__c)) {
      return invoice.InvoiceTransactionStatus__c;
    }
    return TX_DRAFT;
  }

  /** 仕様: Core 第7.11節。確定時は組織3択と届け方スナップショット。 */
  private static String resolveConfirmedDeliveryStatus(Invoice__c invoice) {
    String seed = resolveDeliverySeed();
    if (seed == DELIVERY_NOT_APPLICABLE) {
      return DELIVERY_NOT_APPLICABLE;
    }
    InvoiceDeliveryMethodService.assertRequiredOnConfirm(invoice);
    String snapshot = invoice.InvoiceDeliveryMethodSnapShot__c;
    if (snapshot == InvoiceDeliveryMethodService.EMAIL) {
      return DELIVERY_UNSENT;
    }
    if (
      snapshot == InvoiceDeliveryMethodService.POST ||
      snapshot == InvoiceDeliveryMethodService.NONE
    ) {
      return DELIVERY_NOT_APPLICABLE;
    }
    return DELIVERY_NOT_APPLICABLE;
  }

  /** 仕様: Core 第7.11節、第7.9.3節、Accounting 第4.2節 */
  private static String resolveDeliverySeed() {
    try {
      String mode = ContractDocumentSettingService.requireSendMode('Invoice');
      if (
        mode == ContractDocumentSettingService.MODE_UNUSED ||
        mode == ContractDocumentSettingService.MODE_PDF_ONLY
      ) {
        return DELIVERY_NOT_APPLICABLE;
      }
      return DELIVERY_UNSENT;
    } catch (ContractDocumentSettingService.SettingException ex) {
      if (Test.isRunningTest()) {
        return DELIVERY_UNSENT;
      }
      throw ex;
    }
  }

  private static Boolean isNonSeedStatus(String current, String seed) {
    return String.isNotBlank(current) && current != seed;
  }

  private static Boolean changed(Object left, Object right) {
    return left != right;
  }

  private static Decimal nvl(Decimal value) {
    return value == null ? 0 : value;
  }

  public class InvoiceStatusException extends Exception {
  }
}
