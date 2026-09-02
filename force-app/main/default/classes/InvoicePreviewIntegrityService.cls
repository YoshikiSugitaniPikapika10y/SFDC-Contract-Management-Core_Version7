/**
 * 請求ボード取得時に、請求書と配下明細が同じ契約履歴に属するかを見る。
 */
public without sharing class InvoicePreviewIntegrityService {
  public static final String MISMATCH_MESSAGE = '請求書と配下明細の契約履歴が一致しません。表示も編集も確定もできません。';

  /** 仕様: Core 第7.7.0節 */
  public static void assertSameHistory(Id contractHistoryId, List<Invoice__c> invoices) {
    if (invoices == null || invoices.isEmpty()) {
      return;
    }
    Set<Id> invoiceIds = new Set<Id>();
    Map<Id, Id> historyByInvoiceId = new Map<Id, Id>();
    for (Invoice__c invoice : invoices) {
      if (invoice == null || invoice.Id == null) {
        continue;
      }
      if (
        contractHistoryId != null &&
        invoice.ContractHistory__c != null &&
        invoice.ContractHistory__c != contractHistoryId
      ) {
        throw new IntegrityException(MISMATCH_MESSAGE);
      }
      invoiceIds.add(invoice.Id);
      if (invoice.ContractHistory__c != null) {
        historyByInvoiceId.put(invoice.Id, invoice.ContractHistory__c);
      }
    }
    if (invoiceIds.isEmpty()) {
      return;
    }
    Boolean allHaveEmbeddedLines = true;
    for (Invoice__c invoice : invoices) {
      if (invoice == null || invoice.Id == null) {
        continue;
      }
      if (!invoice.getPopulatedFieldsAsMap().containsKey('InvoiceLines__r')) {
        allHaveEmbeddedLines = false;
        break;
      }
    }
    List<InvoiceLine__c> lines = new List<InvoiceLine__c>();
    Map<Id, Id> lineInvoiceId = new Map<Id, Id>();
    if (allHaveEmbeddedLines) {
      for (Invoice__c invoice : invoices) {
        if (invoice == null || invoice.InvoiceLines__r == null) {
          continue;
        }
        for (InvoiceLine__c line : invoice.InvoiceLines__r) {
          if (line == null) {
            continue;
          }
          lines.add(line);
          lineInvoiceId.put(line.Id, invoice.Id);
        }
      }
    } else {
      lines = [
        SELECT
          Invoice__c,
          Invoice__r.ContractHistory__c,
          ContractProduct__r.ContractHistory__c,
          SourcePeriodLineIds__c
        FROM InvoiceLine__c
        WHERE Invoice__c IN :invoiceIds
        WITH SYSTEM_MODE
      ];
    }
    Set<Id> periodIds = new Set<Id>();
    Map<Id, Id> historyByPeriodId = new Map<Id, Id>();
    for (InvoiceLine__c line : lines) {
      Id parentInvoiceId = lineInvoiceId.containsKey(line.Id)
        ? lineInvoiceId.get(line.Id)
        : line.Invoice__c;
      Id invoiceHistoryId = historyByInvoiceId.get(parentInvoiceId);
      if (invoiceHistoryId == null && !allHaveEmbeddedLines) {
        invoiceHistoryId = line.Invoice__r == null
          ? null
          : line.Invoice__r.ContractHistory__c;
      }
      if (
        line.ContractProduct__r != null &&
        line.ContractProduct__r.ContractHistory__c != null &&
        invoiceHistoryId != null &&
        line.ContractProduct__r.ContractHistory__c != invoiceHistoryId
      ) {
        throw new IntegrityException(MISMATCH_MESSAGE);
      }
      for (Id periodId : parseIds(line.SourcePeriodLineIds__c)) {
        periodIds.add(periodId);
        if (invoiceHistoryId != null) {
          historyByPeriodId.put(periodId, invoiceHistoryId);
        }
      }
    }
    if (periodIds.isEmpty()) {
      return;
    }
    for (InvoiceProduct__c period : [
      SELECT Id, ContractHistory__c
      FROM InvoiceProduct__c
      WHERE Id IN :periodIds
      WITH SYSTEM_MODE
    ]) {
      if (period.ContractHistory__c == null) {
        throw new IntegrityException(MISMATCH_MESSAGE);
      }
      Id expected = historyByPeriodId.containsKey(period.Id)
        ? historyByPeriodId.get(period.Id)
        : contractHistoryId;
      if (expected != null && period.ContractHistory__c != expected) {
        throw new IntegrityException(MISMATCH_MESSAGE);
      }
    }
  }

  private static Set<Id> parseIds(String raw) {
    Set<Id> ids = new Set<Id>();
    if (String.isBlank(raw)) {
      return ids;
    }
    for (String part : raw.split('[^a-zA-Z0-9]')) {
      if (part != null && (part.length() == 15 || part.length() == 18)) {
        try {
          ids.add((Id) part);
        } catch (Exception ignore) {
        }
      }
    }
    return ids;
  }

  public class IntegrityException extends Exception {
  }
}
