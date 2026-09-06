@IsTest
private class FieldCopyDefinitionServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void apply_usesAutoRenewContextOnly() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert new FieldCopyDefinition__c(
        Name = 'Test_AutoRenew_Note',
        TargetObject__c = 'ContractHistory__c',
        Context__c = FieldCopyDefinitionService.CONTEXT_AUTO_RENEW,
        SourceObject__c = 'Account',
        SourceFieldApiName__c = 'Name',
        TargetFieldApiName__c = 'Note__c'
      );

      Account account = new Account(Name = 'コピー元取引先');
      ContractHistory__c autoRenew = new ContractHistory__c();
      FieldCopyDefinitionService.apply(
        autoRenew,
        'ContractHistory__c',
        FieldCopyDefinitionService.CONTEXT_AUTO_RENEW,
        new Map<String, SObject>{ 'Account' => account }
      );
      System.assertEquals(
        'コピー元取引先',
        autoRenew.Note__c,
        '仕様: Core 第11.4.2節 自動Renew'
      );
    }
  }

  @IsTest
  static void apply_autoRenew_skipsNotAutoRenewOnlyDefinition() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert new FieldCopyDefinition__c(
        Name = 'Test_NotAutoRenew_Note',
        TargetObject__c = 'ContractHistory__c',
        Context__c = FieldCopyDefinitionService.CONTEXT_NOT_AUTO_RENEW,
        SourceObject__c = 'Account',
        SourceFieldApiName__c = 'Name',
        TargetFieldApiName__c = 'Note__c'
      );
      ContractHistory__c autoRenew = new ContractHistory__c();
      FieldCopyDefinitionService.apply(
        autoRenew,
        'ContractHistory__c',
        FieldCopyDefinitionService.CONTEXT_AUTO_RENEW,
        new Map<String, SObject>{
          'Account' => new Account(Name = 'コピー元取引先')
        }
      );
      System.assertEquals(
        null,
        autoRenew.Note__c,
        '仕様: Core 第11.4.2節 自動Renew以外だけの行はこの作成では適用しない'
      );

      ContractHistory__c notAuto = new ContractHistory__c();
      FieldCopyDefinitionService.apply(
        notAuto,
        'ContractHistory__c',
        FieldCopyDefinitionService.CONTEXT_NOT_AUTO_RENEW,
        new Map<String, SObject>{
          'Account' => new Account(Name = 'コピー元取引先')
        }
      );
      System.assertEquals(
        'コピー元取引先',
        notAuto.Note__c,
        '仕様: Core 第11.4.2節 自動Renew以外'
      );
    }
  }

  @IsTest
  static void apply_doesNotOverwriteExistingValue() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert new FieldCopyDefinition__c(
        Name = 'Test_Keep_Existing_Note',
        TargetObject__c = 'ContractHistory__c',
        Context__c = FieldCopyDefinitionService.CONTEXT_NOT_AUTO_RENEW,
        SourceObject__c = 'Account',
        SourceFieldApiName__c = 'Name',
        TargetFieldApiName__c = 'Note__c'
      );
      ContractHistory__c history = new ContractHistory__c(Note__c = '画面の値');
      FieldCopyDefinitionService.apply(
        history,
        'ContractHistory__c',
        FieldCopyDefinitionService.CONTEXT_NOT_AUTO_RENEW,
        new Map<String, SObject>{ 'Account' => new Account(Name = 'コピー元') }
      );
      System.assertEquals(
        '画面の値',
        history.Note__c,
        '仕様: Core 第11.4.2節 空欄だけ'
      );
    }
  }

  @IsTest
  static void apply_payment_copiesInvoiceMemo() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert new FieldCopyDefinition__c(
        Name = 'Test_Payment_Memo',
        TargetObject__c = 'InvoicePayment__c',
        SourceObject__c = 'Invoice__c',
        SourceFieldApiName__c = 'Memo__c',
        TargetFieldApiName__c = 'Memo__c'
      );
      InvoicePayment__c payment = new InvoicePayment__c();
      FieldCopyDefinitionService.apply(
        payment,
        'InvoicePayment__c',
        null,
        new Map<String, SObject>{
          'Invoice__c' => new Invoice__c(Memo__c = '請求メモ')
        }
      );
      System.assertEquals(
        '請求メモ',
        payment.Memo__c,
        '仕様: Core 第11.4.2節 入出金はinsert時'
      );
    }
  }

  @IsTest
  static void applyOnInsert_loadsInvoiceSourcesAndCopiesBlankMemo() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert new FieldCopyDefinition__c(
        Name = 'Test_ApplyOnInsert_Memo',
        TargetObject__c = 'Invoice__c',
        SourceObject__c = 'Account',
        SourceFieldApiName__c = 'Name',
        TargetFieldApiName__c = 'Memo__c'
      );
      Account account = ContractTestDataFactory.insertAccount('コピー元取引先');
      BillingAccount__c billingAccount = ContractTestDataFactory.insertBillingAccount(
        account.Id
      );
      ContractService__c service = new ContractService__c(
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id,
        Name = 'ApplyOnInsert Service'
      );
      ContractTestDataFactory.applyRequiredFields(service);
      insert service;
      ContractHistory__c history = new ContractHistory__c(
        ContractService__c = service.Id,
        Name = 'ApplyOnInsert History',
        historystatus__c = 'Estimate',
        Type__c = 'New'
      );
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        history,
        account.Id
      );
      ContractTestDataFactory.applyRequiredFields(history);
      insert history;
      Invoice__c invoice = new Invoice__c(
        ContractHistory__c = history.Id,
        ContractService__c = service.Id
      );

      Test.startTest();
      FieldCopyDefinitionService.applyOnInsert(
        new List<Invoice__c>{ invoice },
        'Invoice__c'
      );
      Test.stopTest();

      System.assertEquals(
        'コピー元取引先',
        invoice.Memo__c,
        '仕様: Core 第11.4.2節 applyOnInsert はコピー元を読んで空欄へ書く'
      );
    }
  }

  @IsTest
  static void validateDefinition_rejectsDeniedPackageField() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      FieldCopyDefinition__c definition = new FieldCopyDefinition__c(
        Name = 'Test_Denied_Amount',
        TargetObject__c = 'Invoice__c',
        SourceObject__c = 'Account',
        SourceFieldApiName__c = 'Name',
        TargetFieldApiName__c = 'Amount__c'
      );
      Boolean rejected = false;
      try {
        FieldCopyDefinitionService.validateDefinition(definition);
      } catch (FieldCopyDefinitionService.FieldCopyException ex) {
        rejected = true;
        System.assert(
          ex.getMessage().contains('Test_Denied_Amount'),
          ex.getMessage()
        );
      }
      System.assertEquals(true, rejected, '仕様: Core 第11.4.2節 拒否リスト');
    }
  }

  @IsTest
  static void validateDefinition_rejectsTypeGroupCross() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      FieldCopyDefinition__c definition = new FieldCopyDefinition__c(
        Name = 'Test_Type_Cross',
        TargetObject__c = 'ContractHistory__c',
        Context__c = FieldCopyDefinitionService.CONTEXT_NOT_AUTO_RENEW,
        SourceObject__c = 'Account',
        SourceFieldApiName__c = 'Name',
        TargetFieldApiName__c = 'EstimateDate__c'
      );
      Boolean rejected = false;
      try {
        FieldCopyDefinitionService.validateDefinition(definition);
      } catch (FieldCopyDefinitionService.FieldCopyException ex) {
        rejected = true;
        System.assert(ex.getMessage().contains('型'), ex.getMessage());
      }
      System.assertEquals(true, rejected, '仕様: Core 第11.4.2節 型グループ');
    }
  }

  @IsTest
  static void insert_rejectsOverlappingTargetField() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert new FieldCopyDefinition__c(
        Name = 'Test_Overlap_A',
        TargetObject__c = 'ContractHistory__c',
        Context__c = FieldCopyDefinitionService.CONTEXT_AUTO_RENEW,
        SourceObject__c = 'Account',
        SourceFieldApiName__c = 'Name',
        TargetFieldApiName__c = 'Note__c'
      );
      Boolean rejected = false;
      try {
        insert new FieldCopyDefinition__c(
          Name = 'Test_Overlap_B',
          TargetObject__c = 'ContractHistory__c',
          Context__c = FieldCopyDefinitionService.CONTEXT_AUTO_RENEW +
            ';' +
            FieldCopyDefinitionService.CONTEXT_NOT_AUTO_RENEW,
          SourceObject__c = 'Account',
          SourceFieldApiName__c = 'Name',
          TargetFieldApiName__c = 'Note__c'
        );
      } catch (DmlException ex) {
        rejected = true;
        System.assert(ex.getMessage().contains('重なって'), ex.getMessage());
      }
      System.assertEquals(true, rejected, '仕様: Core 第11.4.2節 同じTo項目');
    }
  }

  @IsTest
  static void apply_doesNotTruncateOverflow() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert new FieldCopyDefinition__c(
        Name = 'Test_Overflow_Memo',
        TargetObject__c = 'InvoicePayment__c',
        SourceObject__c = 'Invoice__c',
        SourceFieldApiName__c = 'Memo__c',
        TargetFieldApiName__c = 'Memo__c'
      );
      InvoicePayment__c payment = new InvoicePayment__c();
      Boolean rejected = false;
      try {
        FieldCopyDefinitionService.apply(
          payment,
          'InvoicePayment__c',
          null,
          new Map<String, SObject>{
            'Invoice__c' => new Invoice__c(Memo__c = 'あ'.repeat(256))
          }
        );
      } catch (FieldCopyDefinitionService.FieldCopyException ex) {
        rejected = true;
        System.assert(ex.getMessage().contains('桁'), ex.getMessage());
      }
      System.assertEquals(
        true,
        rejected,
        '仕様: Core 第11.4.2節 文字超過は切らない'
      );
      System.assertEquals(null, payment.Memo__c);
    }
  }

  @IsTest
  static void validateAllDefinitions_rejectsInvalidDefinition() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      FieldCopyDefinition__c definition = new FieldCopyDefinition__c(
        Name = 'Test_All_Denied_Amount',
        TargetObject__c = 'Invoice__c',
        SourceObject__c = 'Account',
        SourceFieldApiName__c = 'Name',
        TargetFieldApiName__c = 'Amount__c'
      );
      Boolean rejected = false;
      try {
        FieldCopyDefinitionService.validateAllDefinitions(
          new List<FieldCopyDefinition__c>{ definition }
        );
      } catch (FieldCopyDefinitionService.FieldCopyException ex) {
        rejected = true;
        System.assert(
          ex.getMessage().contains('Test_All_Denied_Amount'),
          ex.getMessage()
        );
      }
      System.assertEquals(
        true,
        rejected,
        'Accounting 第3.1節: コピー設定の妥当性を検証する'
      );
    }
  }

  @IsTest
  static void validateAllDefinitions_rejectsRequiredJournalWithoutBothContexts() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      FieldCopyDefinitionService.additionalRequiredJournalFieldApiNames = new Set<String>{
        'Memo__c'
      };
      insert new FieldCopyDefinition__c(
        Name = 'Test_Journal_Memo_LineOnly',
        TargetObject__c = 'GlJournal__c',
        Context__c = FieldCopyDefinitionService.CONTEXT_LINE_JOURNAL,
        SourceObject__c = 'Account',
        SourceFieldApiName__c = 'Name',
        TargetFieldApiName__c = 'Memo__c'
      );
      Boolean rejected = false;
      try {
        FieldCopyDefinitionService.validateAllDefinitions();
      } catch (FieldCopyDefinitionService.FieldCopyException ex) {
        rejected = true;
        System.assert(ex.getMessage().contains('Memo__c'), ex.getMessage());
      } finally {
        FieldCopyDefinitionService.additionalRequiredJournalFieldApiNames = null;
      }
      System.assertEquals(
        true,
        rejected,
        'Accounting 第3.1節: 仕訳の必須項目は明細外も含む経路で届く定義があること'
      );
    }
  }

  @IsTest
  static void validateDefinition_allowsJournalProductCodeSnapShot() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      FieldCopyDefinitionService.validateDefinition(
        new FieldCopyDefinition__c(
          Name = 'Sample_Journal_ProductCode',
          TargetObject__c = 'GlJournal__c',
          Context__c = FieldCopyDefinitionService.CONTEXT_LINE_JOURNAL,
          SourceObject__c = 'Product2',
          SourceFieldApiName__c = 'ProductCode',
          TargetFieldApiName__c = 'ProductCodeSnapShot__c'
        )
      );
    }
  }

  @IsTest
  static void apply_copiesProductCodeToJournalSnapShotOnLineJournal() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert new FieldCopyDefinition__c(
        Name = 'Test_Journal_ProductCode',
        TargetObject__c = 'GlJournal__c',
        Context__c = FieldCopyDefinitionService.CONTEXT_LINE_JOURNAL,
        SourceObject__c = 'Product2',
        SourceFieldApiName__c = 'ProductCode',
        TargetFieldApiName__c = 'ProductCodeSnapShot__c'
      );
      Product2 product = new Product2(
        Name = 'コード元',
        ProductCode = 'SKU-193'
      );
      GlJournal__c journal = new GlJournal__c();
      FieldCopyDefinitionService.apply(
        journal,
        'GlJournal__c',
        FieldCopyDefinitionService.CONTEXT_LINE_JOURNAL,
        new Map<String, SObject>{ 'Product2' => product }
      );
      System.assertEquals(
        'SKU-193',
        journal.ProductCodeSnapShot__c,
        '仕様: Core 第11.4.2節 Sample_Journal_ProductCode'
      );
      GlJournal__c nonLine = new GlJournal__c();
      FieldCopyDefinitionService.apply(
        nonLine,
        'GlJournal__c',
        FieldCopyDefinitionService.CONTEXT_NON_LINE_JOURNAL,
        new Map<String, SObject>{ 'Product2' => product }
      );
      System.assertEquals(
        null,
        nonLine.ProductCodeSnapShot__c,
        '仕様: Core 第11.4.2節 明細仕訳だけの定義は明細外へ空埋めしない'
      );
    }
  }

  @IsTest
  static void apply_sameCauseSources_stampEachJournalWithoutRedefining() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert new FieldCopyDefinition__c(
        Name = 'Test_Journal_ProductCode_Reuse',
        TargetObject__c = 'GlJournal__c',
        Context__c = FieldCopyDefinitionService.CONTEXT_LINE_JOURNAL,
        SourceObject__c = 'Product2',
        SourceFieldApiName__c = 'ProductCode',
        TargetFieldApiName__c = 'ProductCodeSnapShot__c'
      );
      FieldCopyDefinitionService.resetCache();
      Product2 product = new Product2(
        Name = 'コード元',
        ProductCode = 'SKU-194'
      );
      Map<String, SObject> sources = new Map<String, SObject>{
        'Product2' => product
      };
      GlJournal__c first = new GlJournal__c();
      GlJournal__c second = new GlJournal__c();
      FieldCopyDefinitionService.apply(
        first,
        'GlJournal__c',
        FieldCopyDefinitionService.CONTEXT_LINE_JOURNAL,
        sources
      );
      FieldCopyDefinitionService.apply(
        second,
        'GlJournal__c',
        FieldCopyDefinitionService.CONTEXT_LINE_JOURNAL,
        sources
      );
      System.assertEquals(
        'SKU-194',
        first.ProductCodeSnapShot__c,
        '仕様: Core 第11.4.2節 空欄へコピー'
      );
      System.assertEquals(
        'SKU-194',
        second.ProductCodeSnapShot__c,
        '仕様: Accounting 第8.2節 同じ原因の仕訳へ同じコピー値'
      );
      second.ProductCodeSnapShot__c = '人手';
      FieldCopyDefinitionService.apply(
        second,
        'GlJournal__c',
        FieldCopyDefinitionService.CONTEXT_LINE_JOURNAL,
        sources
      );
      System.assertEquals(
        '人手',
        second.ProductCodeSnapShot__c,
        '仕様: Core 第11.4.2節 空欄だけ'
      );
    }
  }

  @IsTest
  static void validateAllDefinitions_acceptsRequiredJournalCoveredByBothContexts() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      FieldCopyDefinitionService.additionalRequiredJournalFieldApiNames = new Set<String>{
        'Memo__c'
      };
      insert new FieldCopyDefinition__c(
        Name = 'Test_Journal_Memo_Both',
        TargetObject__c = 'GlJournal__c',
        Context__c = FieldCopyDefinitionService.CONTEXT_LINE_JOURNAL +
          ';' +
          FieldCopyDefinitionService.CONTEXT_NON_LINE_JOURNAL,
        SourceObject__c = 'Account',
        SourceFieldApiName__c = 'Name',
        TargetFieldApiName__c = 'Memo__c'
      );
      try {
        FieldCopyDefinitionService.validateAllDefinitions();
      } finally {
        FieldCopyDefinitionService.additionalRequiredJournalFieldApiNames = null;
      }
    }
  }

  @IsTest
  static void apply_allowedHistoryFromToContext_stampsBlank() {
    stampAllowedRows('ContractHistory__c', null, 10);
  }

  @IsTest
  static void apply_allowedInvoiceProductFromToContext_stampsBlank() {
    stampAllowedRows('InvoiceProduct__c', '', 6);
  }

  @IsTest
  static void apply_allowedInvoiceFromToContext_stampsBlank() {
    stampAllowedRows('Invoice__c', '', 6);
  }

  @IsTest
  static void apply_allowedInvoiceLineFromToContext_stampsBlank() {
    stampAllowedRows('InvoiceLine__c', '', 6);
  }

  @IsTest
  static void apply_allowedPaymentFromToContext_stampsBlank() {
    stampAllowedRows('InvoicePayment__c', '', 5);
  }

  @IsTest
  static void apply_allowedLineJournalFromToContext_stampsBlank() {
    stampAllowedRows(
      'GlJournal__c',
      FieldCopyDefinitionService.CONTEXT_LINE_JOURNAL,
      10
    );
  }

  @IsTest
  static void apply_allowedNonLineJournalFromToContext_stampsBlank() {
    stampAllowedRows(
      'GlJournal__c',
      FieldCopyDefinitionService.CONTEXT_NON_LINE_JOURNAL,
      6
    );
  }

  private static void stampAllowedRows(
    String targetObject,
    String contextOrAny,
    Integer expectedCount
  ) {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      List<List<String>> allowed = new List<List<String>>();
      for (List<String> row : allowedFromToContextRows()) {
        if (row[0] != targetObject) {
          continue;
        }
        if (contextOrAny == null || row[1] == contextOrAny) {
          allowed.add(row);
        }
      }
      System.assertEquals(
        expectedCount,
        allowed.size(),
        '仕様: Core 第11.4.2節 To=' + targetObject + ' の許可組み合わせ'
      );
      Integer index = 0;
      for (List<String> row : allowed) {
        stampAllowedBlankCopy(index, row[0], row[1], row[2]);
        index++;
      }
    }
  }

  /** 仕様: Core 第11.4.2節 Toオブジェクトとコンテキスト／仕訳コンテキストの表 */
  private static List<List<String>> allowedFromToContextRows() {
    List<List<String>> rows = new List<List<String>>();
    List<String> historySources = new List<String>{
      'Opportunity',
      'ContractHistory__c',
      'Account',
      'ContractService__c',
      'BillingAccount__c'
    };
    for (String sourceObject : historySources) {
      rows.add(
        new List<String>{
          'ContractHistory__c',
          FieldCopyDefinitionService.CONTEXT_AUTO_RENEW,
          sourceObject
        }
      );
      rows.add(
        new List<String>{
          'ContractHistory__c',
          FieldCopyDefinitionService.CONTEXT_NOT_AUTO_RENEW,
          sourceObject
        }
      );
    }
    List<String> invoiceFamilySources = new List<String>{
      'ContractHistory__c',
      'ContractProduct__c',
      'Product2',
      'BillingAccount__c',
      'Opportunity',
      'Account'
    };
    for (
      String targetObject : new List<String>{
        'InvoiceProduct__c',
        'Invoice__c',
        'InvoiceLine__c'
      }
    ) {
      for (String sourceObject : invoiceFamilySources) {
        rows.add(new List<String>{ targetObject, '', sourceObject });
      }
    }
    for (
      String sourceObject : new List<String>{
        'Invoice__c',
        'BillingAccount__c',
        'ContractHistory__c',
        'Opportunity',
        'Account'
      }
    ) {
      rows.add(new List<String>{ 'InvoicePayment__c', '', sourceObject });
    }
    for (
      String sourceObject : new List<String>{
        'InvoiceLine__c',
        'ContractProduct__c',
        'Product2',
        'InvoicePayment__c',
        'InvoicePaymentAllocation__c',
        'Invoice__c',
        'BillingAccount__c',
        'ContractHistory__c',
        'Opportunity',
        'Account'
      }
    ) {
      rows.add(
        new List<String>{
          'GlJournal__c',
          FieldCopyDefinitionService.CONTEXT_LINE_JOURNAL,
          sourceObject
        }
      );
    }
    for (
      String sourceObject : new List<String>{
        'Invoice__c',
        'BillingAccount__c',
        'ContractHistory__c',
        'Opportunity',
        'Account',
        'InvoicePayment__c'
      }
    ) {
      rows.add(
        new List<String>{
          'GlJournal__c',
          FieldCopyDefinitionService.CONTEXT_NON_LINE_JOURNAL,
          sourceObject
        }
      );
    }
    return rows;
  }

  private static void stampAllowedBlankCopy(
    Integer index,
    String targetObject,
    String context,
    String sourceObject
  ) {
    FieldPair pair = findCopyableFieldPair(targetObject, context, sourceObject);
    System.assertNotEquals(
      null,
      pair,
      '仕様: Core 第11.4.2節 許可組み合わせにコピーできる項目がある To=' +
        targetObject +
        ' Context=' +
        context +
        ' From=' +
        sourceObject
    );
    FieldCopyDefinition__c definition = new FieldCopyDefinition__c(
      Name = ('T601_' + String.valueOf(index)).left(80),
      TargetObject__c = targetObject,
      Context__c = String.isBlank(context) ? null : context,
      SourceObject__c = sourceObject,
      SourceFieldApiName__c = pair.sourceField,
      TargetFieldApiName__c = pair.targetField
    );
    insert definition;
    FieldCopyDefinitionService.resetCache();
    if (globalDescribe == null) {
      globalDescribe = Schema.getGlobalDescribe();
    }
    SObject source = globalDescribe.get(sourceObject).newSObject();
    source.put(pair.sourceField, pair.sampleValue);
    SObject target = globalDescribe.get(targetObject).newSObject();
    String applyContext = String.isBlank(context) ? null : context;
    FieldCopyDefinitionService.apply(
      target,
      targetObject,
      applyContext,
      new Map<String, SObject>{ sourceObject => source }
    );
    System.assertEquals(
      pair.sampleValue,
      target.get(pair.targetField),
      '仕様: Core 第11.4.2節 空欄へコピー To=' +
        targetObject +
        ' Context=' +
        context +
        ' From=' +
        sourceObject
    );
    delete definition;
    FieldCopyDefinitionService.resetCache();
  }

  private class FieldPair {
    String sourceField;
    String targetField;
    Object sampleValue;
  }

  private static Map<String, Schema.SObjectType> globalDescribe;
  private static Map<String, FieldPair> pairByTargetAndSource;
  private static Set<String> unusableTargetFields;

  private static FieldPair findCopyableFieldPair(
    String targetObject,
    String context,
    String sourceObject
  ) {
    if (pairByTargetAndSource == null) {
      pairByTargetAndSource = new Map<String, FieldPair>();
    }
    String cacheKey = targetObject + '\n' + sourceObject;
    if (pairByTargetAndSource.containsKey(cacheKey)) {
      return pairByTargetAndSource.get(cacheKey);
    }
    if (globalDescribe == null) {
      globalDescribe = Schema.getGlobalDescribe();
    }
    if (unusableTargetFields == null) {
      unusableTargetFields = new Set<String>();
    }
    Map<String, Schema.SObjectField> sourceFields = globalDescribe.get(
        sourceObject
      )
      .getDescribe()
      .fields.getMap();
    Map<String, Schema.SObjectField> targetFields = globalDescribe.get(
        targetObject
      )
      .getDescribe()
      .fields.getMap();
    List<String> sourceCandidates = orderedFieldApiNames(sourceFields);
    List<String> targetCandidates = orderedFieldApiNames(targetFields);
    Set<String> hardcoded = InvoiceProductFieldCopyService.getHardcodedTargetFieldApiNames(
      targetObject
    );
    FieldPair found;
    for (String sourceField : sourceCandidates) {
      Schema.DescribeFieldResult sourceDescribe = sourceFields.get(sourceField)
        .getDescribe();
      Object sampleValue = sampleValueFor(sourceDescribe);
      if (sampleValue == null) {
        continue;
      }
      for (String targetField : targetCandidates) {
        String unusableKey = targetObject + '.' + targetField;
        if (unusableTargetFields.contains(unusableKey)) {
          continue;
        }
        if (hardcoded != null && hardcoded.contains(targetField)) {
          unusableTargetFields.add(unusableKey);
          continue;
        }
        Schema.DescribeFieldResult targetDescribe = targetFields.get(
            targetField
          )
          .getDescribe();
        if (
          targetDescribe == null ||
          !targetDescribe.isUpdateable() ||
          targetDescribe.isCalculated()
        ) {
          unusableTargetFields.add(unusableKey);
          continue;
        }
        FieldCopyDefinition__c candidate = new FieldCopyDefinition__c(
          Name = 'T601_probe',
          TargetObject__c = targetObject,
          Context__c = String.isBlank(context) ? null : context,
          SourceObject__c = sourceObject,
          SourceFieldApiName__c = sourceField,
          TargetFieldApiName__c = targetField
        );
        try {
          FieldCopyDefinitionService.validateDefinition(candidate);
        } catch (FieldCopyDefinitionService.FieldCopyException ex) {
          String message = ex.getMessage();
          if (
            message != null &&
            (message.contains('パッケージ項目') ||
            message.contains('ハードコード') ||
            message.contains('書けません') ||
            message.contains('To項目がありません'))
          ) {
            unusableTargetFields.add(unusableKey);
          }
          continue;
        }
        found = new FieldPair();
        found.sourceField = sourceField;
        found.targetField = targetField;
        found.sampleValue = sampleValue;
        break;
      }
      if (found != null) {
        break;
      }
    }
    pairByTargetAndSource.put(cacheKey, found);
    return found;
  }

  private static List<String> orderedFieldApiNames(
    Map<String, Schema.SObjectField> fields
  ) {
    List<String> preferred = new List<String>{
      'Name',
      'ProductCode',
      'Note__c',
      'Memo__c',
      'Description__c',
      'CustomerMemo__c',
      'BillingAddressee__c',
      'ProductName__c',
      'ProductCodeSnapShot__c',
      'CancellationReasonText__c',
      'UnlockReason__c',
      'TaxInclusiveCommaText__c',
      'Amount__c'
    };
    List<String> ordered = new List<String>();
    Set<String> seen = new Set<String>();
    for (String apiName : preferred) {
      if (fields.containsKey(apiName)) {
        ordered.add(apiName);
        seen.add(apiName.toLowerCase());
      }
    }
    List<String> rest = new List<String>(fields.keySet());
    rest.sort();
    for (String apiName : rest) {
      if (!seen.contains(apiName.toLowerCase())) {
        ordered.add(apiName);
      }
    }
    return ordered;
  }

  private static Object sampleValueFor(Schema.DescribeFieldResult describe) {
    if (
      describe == null ||
      !describe.isUpdateable() ||
      describe.isCalculated()
    ) {
      return null;
    }
    Schema.DisplayType fieldType = describe.getType();
    if (
      fieldType == Schema.DisplayType.STRING ||
      fieldType == Schema.DisplayType.TEXTAREA ||
      fieldType == Schema.DisplayType.EMAIL ||
      fieldType == Schema.DisplayType.PHONE ||
      fieldType == Schema.DisplayType.URL ||
      fieldType == Schema.DisplayType.PICKLIST
    ) {
      String value = 'T601';
      Integer maxLength = describe.getLength();
      if (maxLength != null && maxLength > 0 && value.length() > maxLength) {
        value = value.left(maxLength);
      }
      return value;
    }
    if (
      fieldType == Schema.DisplayType.DOUBLE ||
      fieldType == Schema.DisplayType.CURRENCY ||
      fieldType == Schema.DisplayType.PERCENT ||
      fieldType == Schema.DisplayType.INTEGER ||
      fieldType == Schema.DisplayType.LONG
    ) {
      return 12;
    }
    if (fieldType == Schema.DisplayType.BOOLEAN) {
      return true;
    }
    if (fieldType == Schema.DisplayType.DATE) {
      return Date.newInstance(2026, 9, 7);
    }
    if (fieldType == Schema.DisplayType.DATETIME) {
      return Datetime.newInstance(2026, 9, 7, 0, 0, 0);
    }
    return null;
  }
}
