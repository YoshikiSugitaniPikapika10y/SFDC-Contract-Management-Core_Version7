/**
 * 請求入出金のガード。登録・取消の正本は InvoicePaymentService。
 */
public without sharing class InvoicePaymentTriggerHandler {
  public static final String PERMISSION_REQUIRED_MESSAGE = '入金の作成・更新・削除には入金（13）権限が必要です。';
  public static final String DRAFT_PAYMENT_BLOCK_MESSAGE = '未確定の請求には入金を登録できません。確定後に登録してください。';
  public static final String ZERO_AMOUNT_BLOCK_MESSAGE = '入出金金額は0以外の整数を指定してください。';
  public static final String PURPOSE_BLOCK_MESSAGE = '入出金目的は請求金額または請求金額以外です。';
  public static final String DIRECT_UPDATE_BLOCK_MESSAGE = '入金は直接更新できません。取消で訂正してください。';
  public static final String DELETE_BLOCK_MESSAGE = '請求入出金は削除できません。取消してください。';
  public static final String INVOICE_ALLOCATION_REQUIRED_MESSAGE =
    '請求金額の入出金は明細別割当が1件以上必要です。';

  /** 仕様: Core 第8.1節、第11.4.2節 */
  public static void handleBeforeInsert(List<InvoicePayment__c> payments) {
    assertPermission(payments);
    seedActiveStatus(payments);
    validateAmounts(payments);
    validatePurpose(payments);
    validateParentsAllowPayment(payments);
    applyFieldCopy(payments);
  }

  private static void seedActiveStatus(List<InvoicePayment__c> payments) {
    if (payments == null) {
      return;
    }
    for (InvoicePayment__c payment : payments) {
      if (payment != null && String.isBlank(payment.PaymentTransactionStatus__c)) {
        payment.PaymentTransactionStatus__c = InvoicePaymentService.STATUS_ACTIVE;
      }
    }
  }

  public static void handleBeforeUpdate(
    List<InvoicePayment__c> payments,
    Map<Id, InvoicePayment__c> oldMap
  ) {
    if (InvoicePaymentService.allowLifecycleWrite == true) {
      return;
    }
    assertPermission(payments);
    for (InvoicePayment__c payment : payments) {
      if (payment == null) {
        continue;
      }
      InvoicePayment__c prior = oldMap == null ? null : oldMap.get(payment.Id);
      try {
        // 仕様: Core 第8.4節、第11.6節。除外項目だけの更新は許す。金額・日付・目的は不可。
        InvoicePaymentLockUtil.assertExemptUpdate(prior, payment);
      } catch (InvoicePaymentLockUtil.LockExemptException ex) {
        payment.addError(ex.getMessage());
      }
    }
  }

  /** 仕様: 共通基盤 第3.6節。物理削除は 101／103（hasDeleteRecords。101 は 103 を含む）。 */
  public static void handleBeforeDelete(List<InvoicePayment__c> payments) {
    if (ContractPermissionUtil.hasDeleteRecords()) {
      return;
    }
    assertPermission(payments);
    if (payments == null) {
      return;
    }
    for (InvoicePayment__c payment : payments) {
      if (payment != null) {
        payment.addError(DELETE_BLOCK_MESSAGE);
      }
    }
  }

  /** 仕様: Core 第8.6節、第8.9節。画面以外の全経路でも Invoice 目的は割当1件以上。 */
  public static void handleAfterInsert(List<InvoicePayment__c> payments) {
    assertInvoiceAllocations(payments);
    InvoicePaymentService.recalculateNets(collectInvoiceIds(payments));
  }

  public static void handleAfterUpdate(
    List<InvoicePayment__c> payments,
    Map<Id, InvoicePayment__c> oldMap
  ) {
    Set<Id> invoiceIds = collectInvoiceIds(payments);
    invoiceIds.addAll(collectInvoiceIds(oldMap == null ? null : oldMap.values()));
    InvoicePaymentService.recalculateNets(invoiceIds);
  }

  public static void handleAfterDelete(List<InvoicePayment__c> payments) {
    InvoicePaymentService.recalculateNets(collectInvoiceIds(payments));
  }

  /** 仕様: Core 第8.6節、第8.9節。register は割当挿入までフラグを立てる。直接DMLは拒否。 */
  private static void assertInvoiceAllocations(List<InvoicePayment__c> payments) {
    if (
      payments == null ||
      payments.isEmpty() ||
      InvoicePaymentService.allowLifecycleWrite == true
    ) {
      return;
    }
    Set<Id> invoicePurposeIds = new Set<Id>();
    for (InvoicePayment__c payment : payments) {
      if (
        payment != null &&
        payment.Id != null &&
        payment.PaymentPurpose__c == InvoicePaymentService.PURPOSE_INVOICE
      ) {
        invoicePurposeIds.add(payment.Id);
      }
    }
    if (invoicePurposeIds.isEmpty()) {
      return;
    }
    Set<Id> allocatedIds = new Set<Id>();
    for (InvoicePaymentAllocation__c allocation : [
      SELECT InvoicePayment__c
      FROM InvoicePaymentAllocation__c
      WHERE InvoicePayment__c IN :invoicePurposeIds
      WITH SYSTEM_MODE
    ]) {
      allocatedIds.add(allocation.InvoicePayment__c);
    }
    for (InvoicePayment__c payment : payments) {
      if (
        payment != null &&
        invoicePurposeIds.contains(payment.Id) &&
        !allocatedIds.contains(payment.Id)
      ) {
        payment.addError(INVOICE_ALLOCATION_REQUIRED_MESSAGE);
      }
    }
  }

  private static void assertPermission(List<InvoicePayment__c> payments) {
    if (
      payments == null ||
      payments.isEmpty() ||
      InvoicePaymentService.allowLifecycleWrite == true ||
      ContractPermissionUtil.has(ContractPermissionUtil.INVOICE_PAYMENT) ||
      ContractPermissionUtil.hasMigrateAll()
    ) {
      return;
    }
    for (InvoicePayment__c payment : payments) {
      if (payment != null) {
        payment.addError(PERMISSION_REQUIRED_MESSAGE);
      }
    }
  }

  /** 仕様: Core 第8.1節、第8.2節 */
  private static void validatePurpose(List<InvoicePayment__c> payments) {
    if (payments == null) {
      return;
    }
    for (InvoicePayment__c payment : payments) {
      if (payment == null) {
        continue;
      }
      if (
        payment.PaymentPurpose__c != InvoicePaymentService.PURPOSE_INVOICE &&
        payment.PaymentPurpose__c != InvoicePaymentService.PURPOSE_NON_INVOICE
      ) {
        payment.addError(PURPOSE_BLOCK_MESSAGE);
      }
    }
  }

  /** 仕様: Core 第8.1節、第8.3節 */
  private static void validateAmounts(List<InvoicePayment__c> payments) {
    if (payments == null) {
      return;
    }
    for (InvoicePayment__c payment : payments) {
      if (payment == null) {
        continue;
      }
      if (payment.Amount__c == null || payment.Amount__c == 0) {
        payment.addError(ZERO_AMOUNT_BLOCK_MESSAGE);
        continue;
      }
      if (payment.Amount__c != payment.Amount__c.intValue()) {
        payment.addError(ZERO_AMOUNT_BLOCK_MESSAGE);
      }
    }
  }

  /** 仕様: Core 第8.1節、第7.11節 */
  private static void validateParentsAllowPayment(
    List<InvoicePayment__c> payments
  ) {
    Set<Id> invoiceIds = collectInvoiceIds(payments);
    if (invoiceIds.isEmpty()) {
      return;
    }
    Map<Id, Invoice__c> invoices = new Map<Id, Invoice__c>(
      [
        SELECT
          Id,
          InvoiceTransactionStatus__c
        FROM Invoice__c
        WHERE Id IN :invoiceIds
        WITH SYSTEM_MODE
      ]
    );
    for (InvoicePayment__c payment : payments) {
      if (payment == null || payment.Invoice__c == null) {
        continue;
      }
      Invoice__c invoice = invoices.get(payment.Invoice__c);
      if (invoice == null || InvoiceTransactionStatusService.isCancelled(invoice)) {
        payment.addError('取消済みの請求に入出金は登録できません。');
        continue;
      }
      if (!InvoiceTransactionStatusService.isConfirmed(invoice)) {
        payment.addError(DRAFT_PAYMENT_BLOCK_MESSAGE);
      }
    }
  }

  private static Set<Id> collectInvoiceIds(List<InvoicePayment__c> payments) {
    Set<Id> ids = new Set<Id>();
    if (payments == null) {
      return ids;
    }
    for (InvoicePayment__c payment : payments) {
      if (payment != null && payment.Invoice__c != null) {
        ids.add(payment.Invoice__c);
      }
    }
    return ids;
  }

  /** 仕様: Core 第11.4.2節 */
  private static void applyFieldCopy(List<InvoicePayment__c> payments) {
    if (payments == null || payments.isEmpty()) {
      return;
    }
    Set<Id> invoiceIds = collectInvoiceIds(payments);
    Map<Id, SObject> invoiceById = new Map<Id, SObject>();
    Map<Id, SObject> billingById = new Map<Id, SObject>();
    Map<Id, SObject> historyById = new Map<Id, SObject>();
    Map<Id, SObject> opportunityById = new Map<Id, SObject>();
    Map<Id, SObject> accountById = new Map<Id, SObject>();
    for (Id invoiceId : invoiceIds) {
      SObject invoice = InvoiceProductFieldCopyService.querySourceRecord(
        InvoiceProductFieldCopyService.OBJECT_INVOICE,
        invoiceId
      );
      if (invoice != null) {
        invoiceById.put(invoiceId, invoice);
      }
    }
    Set<Id> billingIds = new Set<Id>();
    Set<Id> historyIds = new Set<Id>();
    for (SObject invoice : invoiceById.values()) {
      Id billingId = (Id) invoice.get('BillingAccountSnapShot__c');
      if (billingId != null) {
        billingIds.add(billingId);
      }
      Id historyId = (Id) invoice.get('ContractHistory__c');
      if (historyId != null) {
        historyIds.add(historyId);
      }
    }
    for (Id billingId : billingIds) {
      SObject billing = InvoiceProductFieldCopyService.querySourceRecord(
        InvoiceProductFieldCopyService.OBJECT_BILLING_ACCOUNT,
        billingId
      );
      if (billing != null) {
        billingById.put(billingId, billing);
      }
    }
    for (Id historyId : historyIds) {
      SObject history = InvoiceProductFieldCopyService.querySourceRecord(
        InvoiceProductFieldCopyService.OBJECT_CONTRACT_HISTORY,
        historyId
      );
      if (history != null) {
        historyById.put(historyId, history);
        Id opportunityId = (Id) history.get('Opportunity__c');
        if (opportunityId != null) {
          SObject opportunity = InvoiceProductFieldCopyService.querySourceRecord(
            InvoiceProductFieldCopyService.OBJECT_OPPORTUNITY,
            opportunityId
          );
          if (opportunity != null) {
            opportunityById.put(opportunityId, opportunity);
            Id accountId = (Id) opportunity.get('AccountId');
            if (accountId != null) {
              SObject account = InvoiceProductFieldCopyService.querySourceRecord(
                InvoiceProductFieldCopyService.OBJECT_ACCOUNT,
                accountId
              );
              if (account != null) {
                accountById.put(accountId, account);
              }
            }
          }
        }
      }
    }
    for (InvoicePayment__c payment : payments) {
      if (payment == null || payment.Invoice__c == null) {
        continue;
      }
      Map<String, SObject> sources = new Map<String, SObject>();
      SObject invoice = invoiceById.get(payment.Invoice__c);
      if (invoice != null) {
        sources.put('Invoice__c', invoice);
        SObject billing = billingById.get((Id) invoice.get('BillingAccountSnapShot__c'));
        if (billing != null) {
          sources.put('BillingAccount__c', billing);
        }
        SObject history = historyById.get((Id) invoice.get('ContractHistory__c'));
        if (history != null) {
          sources.put('ContractHistory__c', history);
          SObject opportunity = opportunityById.get((Id) history.get('Opportunity__c'));
          if (opportunity != null) {
            sources.put('Opportunity', opportunity);
            SObject account = accountById.get((Id) opportunity.get('AccountId'));
            if (account != null) {
              sources.put('Account', account);
            }
          }
        }
      }
      FieldCopyDefinitionService.apply(
        payment,
        'InvoicePayment__c',
        null,
        sources
      );
    }
  }
}
