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
        new Map<String, SObject>{ 'Account' => new Account(Name = 'コピー元取引先') }
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
        new Map<String, SObject>{ 'Account' => new Account(Name = 'コピー元取引先') }
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
      System.assertEquals('画面の値', history.Note__c, '仕様: Core 第11.4.2節 空欄だけ');
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
        System.assert(ex.getMessage().contains('Test_Denied_Amount'), ex.getMessage());
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
      System.assertEquals(true, rejected, '仕様: Core 第11.4.2節 文字超過は切らない');
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
      Product2 product = new Product2(Name = 'コード元', ProductCode = 'SKU-193');
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
}
