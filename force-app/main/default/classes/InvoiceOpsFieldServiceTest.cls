@IsTest
private class InvoiceOpsFieldServiceTest {
  @IsTest
  static void getDefinitions_rejectsInvoicePurposeFlagOnInvoice() {
    InvoiceOpsField__mdt row = new InvoiceOpsField__mdt(
      DeveloperName = 'BadInvoiceFlag',
      Active__c = true,
      TargetObject__c = 'Invoice__c',
      FieldApiName__c = 'Memo__c',
      ShowOnInvoicePurpose__c = true,
      ShowOnNonInvoicePurpose__c = false
    );
    InvoiceOpsFieldService.setCachedRowsForTest(
      new List<InvoiceOpsField__mdt>{ row }
    );
    Boolean thrown = false;
    try {
      InvoiceOpsFieldService.getDefinitions();
    } catch (AuraHandledException ex) {
      thrown = true;
      System.assert(
        ex.getMessage().contains('BadInvoiceFlag'),
        '仕様: Core 第11.4.4節 エラーに DeveloperName を含める。実際: ' +
          ex.getMessage()
      );
      System.assert(
        ex.getMessage().contains('Purpose'),
        ex.getMessage()
      );
    }
    System.assertEquals(true, thrown);
    InvoiceOpsFieldService.resetCache();
  }

  @IsTest
  static void getDefinitions_rejectsMissingField() {
    InvoiceOpsField__mdt row = new InvoiceOpsField__mdt(
      DeveloperName = 'MissingField',
      Active__c = true,
      TargetObject__c = 'InvoicePayment__c',
      FieldApiName__c = 'DoesNotExist__c',
      ShowOnInvoicePurpose__c = true,
      ShowOnNonInvoicePurpose__c = false
    );
    InvoiceOpsFieldService.setCachedRowsForTest(
      new List<InvoiceOpsField__mdt>{ row }
    );
    Boolean thrown = false;
    try {
      InvoiceOpsFieldService.getDefinitions();
    } catch (AuraHandledException ex) {
      thrown = true;
      System.assert(
        ex.getMessage().contains('MissingField'),
        ex.getMessage()
      );
      System.assert(
        ex.getMessage().contains('存在しません'),
        ex.getMessage()
      );
    }
    System.assertEquals(true, thrown);
    InvoiceOpsFieldService.resetCache();
  }

  @IsTest
  static void getDefinitions_rejectsPurposeFlagOnJournal() {
    InvoiceOpsField__mdt row = new InvoiceOpsField__mdt(
      DeveloperName = 'BadJournalFlag',
      Active__c = true,
      TargetObject__c = 'GlJournal__c',
      FieldApiName__c = 'Memo__c',
      ShowOnInvoicePurpose__c = false,
      ShowOnNonInvoicePurpose__c = true
    );
    InvoiceOpsFieldService.setCachedRowsForTest(
      new List<InvoiceOpsField__mdt>{ row }
    );
    Boolean thrown = false;
    try {
      InvoiceOpsFieldService.getDefinitions();
    } catch (AuraHandledException ex) {
      thrown = true;
      System.assert(
        ex.getMessage().contains('BadJournalFlag'),
        '仕様: Core 第11.4.4節 エラーに DeveloperName を含める。実際: ' +
          ex.getMessage()
      );
    }
    System.assertEquals(true, thrown);
    InvoiceOpsFieldService.resetCache();
  }

  @IsTest
  static void journalScreenFieldApiNames_returnsGlJournalOnly() {
    InvoiceOpsField__mdt invoice = new InvoiceOpsField__mdt(
      DeveloperName = 'InvMemo',
      Active__c = true,
      TargetObject__c = 'Invoice__c',
      FieldApiName__c = 'Memo__c'
    );
    InvoiceOpsField__mdt journal = new InvoiceOpsField__mdt(
      DeveloperName = 'JnlMemo',
      Active__c = true,
      TargetObject__c = 'GlJournal__c',
      FieldApiName__c = 'Memo__c'
    );
    InvoiceOpsFieldService.setCachedRowsForTest(
      new List<InvoiceOpsField__mdt>{ invoice, journal }
    );
    Set<String> names = InvoiceOpsFieldService.journalScreenFieldApiNames();
    System.assertEquals(true, names.contains('Memo__c'));
    System.assertEquals(1, names.size());
    InvoiceOpsFieldService.resetCache();
  }

  @IsTest
  static void paymentDisplayedFieldApiNames_skipsOtherPurposeRequired() {
    InvoiceOpsField__mdt hiddenRequired = new InvoiceOpsField__mdt(
      DeveloperName = 'HiddenRequired',
      Active__c = true,
      TargetObject__c = 'InvoicePayment__c',
      FieldApiName__c = 'Memo__c',
      LabelOverride__c = '隠し必須',
      Required__c = true,
      ShowOnInvoicePurpose__c = false,
      ShowOnNonInvoicePurpose__c = true
    );
    InvoiceOpsFieldService.setCachedRowsForTest(
      new List<InvoiceOpsField__mdt>{ hiddenRequired }
    );
    Set<String> invoiceShown = InvoiceOpsFieldService.paymentDisplayedFieldApiNames(
      'Invoice'
    );
    System.assertEquals(
      false,
      invoiceShown.contains('Memo__c'),
      'Core 第11.4.4節: Invoice Purpose で非表示の項目は必須判定しない'
    );
    InvoicePayment__c payment = new InvoicePayment__c();
    InvoiceOpsFieldService.applyDisplayedValues(
      payment,
      'InvoicePayment__c',
      new Map<String, Object>(),
      invoiceShown
    );
    InvoiceOpsFieldService.resetCache();
  }
}
