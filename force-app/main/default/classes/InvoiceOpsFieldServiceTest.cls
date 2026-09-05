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
      System.assertEquals(
        '請求操作追加項目「BadInvoiceFlag」は請求書・仕訳に Purpose 表示旗を立てられません。',
        ex.getMessage(),
        '仕様: Core 第11.4.4節 エラーに DeveloperName を含める'
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
      System.assertEquals(
        '請求操作追加項目「MissingField」の項目「DoesNotExist__c」が対象オブジェクトに存在しません。',
        ex.getMessage(),
        'Core 第11.4.4節: 無い項目は DeveloperName 付きで拒否する'
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
      System.assertEquals(
        '請求操作追加項目「BadJournalFlag」は請求書・仕訳に Purpose 表示旗を立てられません。',
        ex.getMessage(),
        '仕様: Core 第11.4.4節 エラーに DeveloperName を含める'
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

  @IsTest
  static void getDefinitions_skipsInactiveAndKeepsFixedDefault() {
    InvoiceOpsField__mdt inactive = new InvoiceOpsField__mdt(
      DeveloperName = 'InactiveMemo',
      Active__c = false,
      TargetObject__c = 'Invoice__c',
      FieldApiName__c = 'Memo__c',
      DefaultValue__c = 'ignored'
    );
    InvoiceOpsField__mdt active = new InvoiceOpsField__mdt(
      DeveloperName = 'ActiveMemo',
      Active__c = true,
      TargetObject__c = 'Invoice__c',
      FieldApiName__c = 'Memo__c',
      LabelOverride__c = '請求メモ',
      DefaultValue__c = '固定初期値'
    );
    InvoiceOpsFieldService.setCachedRowsForTest(
      new List<InvoiceOpsField__mdt>{ inactive, active }
    );
    List<InvoiceOpsFieldService.FieldDefinition> rows = InvoiceOpsFieldService.getDefinitions();
    System.assertEquals(1, rows.size(), 'Core 第11.4.4節: Active=true だけを対象とする');
    System.assertEquals('ActiveMemo', rows[0].developerName);
    System.assertEquals(
      '固定初期値',
      rows[0].defaultValue,
      'Core 第11.4.4節: 初期値は DefaultValue の固定文字列だけ'
    );
    System.assertEquals('請求メモ', rows[0].label);
    InvoiceOpsFieldService.resetCache();
  }

  @IsTest
  static void getDefinitions_rejectsUnknownTargetObject() {
    InvoiceOpsField__mdt row = new InvoiceOpsField__mdt(
      DeveloperName = 'BadTarget',
      Active__c = true,
      TargetObject__c = 'Account',
      FieldApiName__c = 'Name'
    );
    InvoiceOpsFieldService.setCachedRowsForTest(
      new List<InvoiceOpsField__mdt>{ row }
    );
    Boolean thrown = false;
    try {
      InvoiceOpsFieldService.getDefinitions();
    } catch (AuraHandledException ex) {
      thrown = true;
      System.assertEquals(
        '請求操作追加項目「BadTarget」の対象オブジェクト「Account」が不正です。Invoice__c / InvoicePayment__c / GlJournal__c のいずれかを指定してください。',
        ex.getMessage(),
        'Core 第11.4.4節: エラーに DeveloperName を含める'
      );
    }
    System.assertEquals(true, thrown);
    InvoiceOpsFieldService.resetCache();
  }

  @IsTest
  static void paymentDisplayedFieldApiNames_unsetFlagsAreHidden() {
    InvoiceOpsField__mdt unsetFlags = new InvoiceOpsField__mdt(
      DeveloperName = 'UnsetPaymentMemo',
      Active__c = true,
      TargetObject__c = 'InvoicePayment__c',
      FieldApiName__c = 'Memo__c',
      Required__c = true
    );
    InvoiceOpsFieldService.setCachedRowsForTest(
      new List<InvoiceOpsField__mdt>{ unsetFlags }
    );
    System.assertEquals(
      false,
      InvoiceOpsFieldService.paymentDisplayedFieldApiNames('Invoice')
        .contains('Memo__c'),
      'Core 第11.4.4節: 入出金の表示旗は明示 true だけ。未設定は非表示'
    );
    System.assertEquals(
      false,
      InvoiceOpsFieldService.paymentDisplayedFieldApiNames('NonInvoice')
        .contains('Memo__c'),
      'Core 第11.4.4節: 入出金の表示旗は明示 true だけ。未設定は非表示'
    );
    InvoiceOpsFieldService.resetCache();
  }

  @IsTest
  static void applyDisplayedValues_requiredDisplayedRejectsBlank() {
    InvoiceOpsField__mdt requiredMemo = new InvoiceOpsField__mdt(
      DeveloperName = 'RequiredMemo',
      Active__c = true,
      TargetObject__c = 'Invoice__c',
      FieldApiName__c = 'Memo__c',
      LabelOverride__c = '必須メモ',
      Required__c = true
    );
    InvoiceOpsFieldService.setCachedRowsForTest(
      new List<InvoiceOpsField__mdt>{ requiredMemo }
    );
    Boolean thrown = false;
    try {
      InvoiceOpsFieldService.applyDisplayedValues(
        new Invoice__c(),
        'Invoice__c',
        new Map<String, Object>(),
        new Set<String>{ 'Memo__c' }
      );
    } catch (AuraHandledException ex) {
      thrown = true;
      System.assertEquals(
        '請求操作追加項目「必須メモ」は必須です。',
        ex.getMessage(),
        'Core 第11.4.4節: 画面に表示されている場合だけ必須'
      );
    }
    System.assertEquals(true, thrown);
    InvoiceOpsFieldService.resetCache();
  }

  @IsTest
  static void fieldApiNames_returnsInvoiceDefinitionsOnly() {
    InvoiceOpsField__mdt invoice = new InvoiceOpsField__mdt(
      DeveloperName = 'InvMemoOnly',
      Active__c = true,
      TargetObject__c = 'Invoice__c',
      FieldApiName__c = 'Memo__c'
    );
    InvoiceOpsField__mdt payment = new InvoiceOpsField__mdt(
      DeveloperName = 'PayMemoOnly',
      Active__c = true,
      TargetObject__c = 'InvoicePayment__c',
      FieldApiName__c = 'Memo__c',
      ShowOnInvoicePurpose__c = true
    );
    InvoiceOpsFieldService.setCachedRowsForTest(
      new List<InvoiceOpsField__mdt>{ invoice, payment }
    );
    Set<String> invoiceNames = InvoiceOpsFieldService.fieldApiNames(
      'Invoice__c'
    );
    System.assertEquals(true, invoiceNames.contains('Memo__c'));
    System.assertEquals(1, invoiceNames.size());
    System.assertEquals(
      0,
      InvoiceOpsFieldService.readValuesById(
          'Invoice__c',
          new Set<Id>()
        )
        .size()
    );
    InvoiceOpsFieldService.resetCache();
  }
}
