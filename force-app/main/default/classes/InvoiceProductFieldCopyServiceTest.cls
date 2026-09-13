@IsTest
private class InvoiceProductFieldCopyServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountInstallService.seedOnInstall();
    }
  }

  @IsTest
  static void getActiveDefinitions_includesOneSamplePerTargetObject() {
    InvoiceProductFieldCopyService.resetCache();
    Map<String, FieldCopyDefinition__c> invoiceDefinitionsByName = new Map<String, FieldCopyDefinition__c>();
    for (
      FieldCopyDefinition__c definition : InvoiceProductFieldCopyService.getActiveDefinitions(
        InvoiceProductFieldCopyService.TARGET_INVOICE
      )
    ) {
      invoiceDefinitionsByName.put(definition.Name, definition);
    }
    Map<String, FieldCopyDefinition__c> lineDefinitionsByName = new Map<String, FieldCopyDefinition__c>();
    for (
      FieldCopyDefinition__c definition : InvoiceProductFieldCopyService.getActiveDefinitions(
        InvoiceProductFieldCopyService.TARGET_INVOICE_LINE
      )
    ) {
      lineDefinitionsByName.put(definition.Name, definition);
    }

    FieldCopyDefinition__c invoiceSample = invoiceDefinitionsByName.get(
      'Sample_Inv_AccountName'
    );
    System.assertNotEquals(
      null,
      invoiceSample,
      '仕様: Core 第11.4.2節 標準見本 Sample_Inv_AccountName を初回に置く'
    );
    System.assertEquals(
      'Account',
      invoiceSample.SourceObject__c,
      '仕様: Core 第11.4.2節 請求書見本の From は取引先'
    );
    System.assertEquals(
      'Name',
      invoiceSample.SourceFieldApiName__c,
      '仕様: Core 第11.4.2節 請求書見本は取引先名を読む'
    );
    System.assertEquals(
      'Memo__c',
      invoiceSample.TargetFieldApiName__c,
      '仕様: Core 第11.4.2節 請求書見本の To はメモ'
    );

    FieldCopyDefinition__c lineSample = lineDefinitionsByName.get(
      'Sample_Line_ProductCode'
    );
    System.assertNotEquals(
      null,
      lineSample,
      '仕様: Core 第11.4.2節 標準見本 Sample_Line_ProductCode を初回に置く'
    );
    System.assertEquals(
      'Product2',
      lineSample.SourceObject__c,
      '仕様: Core 第11.4.2節 請求明細見本の From は商品'
    );
    System.assertEquals(
      'ProductCode',
      lineSample.SourceFieldApiName__c,
      '仕様: Core 第11.4.2節 請求明細見本は商品コードを読む'
    );
    System.assertEquals(
      'ProductCodeSnapShot__c',
      lineSample.TargetFieldApiName__c,
      '仕様: Core 第11.4.2節 請求明細見本の To は商品コード SnapShot'
    );
    System.assertEquals(
      0,
      InvoiceProductFieldCopyService.getActiveDefinitions(
          InvoiceProductFieldCopyService.TARGET_INVOICE_PRODUCT
        )
        .size(),
      '仕様: Core 第11.4.2節 期間明細への取引先名見本は置かない'
    );
  }

  @IsTest
  static void applyCopies_toInvoice_copiesSampleAccountName() {
    InvoiceProductFieldCopyService.resetCache();
    InvoiceProductFieldCopyService.cachedDefinitions = new List<FieldCopyDefinition__c>{
      new FieldCopyDefinition__c(
        Name = 'Test_Inv_AccountName',
        SourceObject__c = 'Account',
        SourceFieldApiName__c = 'Name',
        TargetFieldApiName__c = 'Memo__c',
        TargetObject__c = 'Invoice__c'
      )
    };

    Invoice__c invoice = new Invoice__c();
    Test.startTest();
    InvoiceProductFieldCopyService.applyCopies(
      invoice,
      InvoiceProductFieldCopyService.TARGET_INVOICE,
      new Map<String, SObject>{
        'Account' => new Account(Name = 'サンプル取引先')
      }
    );
    Test.stopTest();

    System.assertEquals(
      'サンプル取引先',
      invoice.Memo__c,
      '仕様: Core 第11.4.2節 作成時の空欄へ定義値をコピーする'
    );
  }

  @IsTest
  static void applyCopies_doesNotOverwriteExistingTargetValues() {
    InvoiceProductFieldCopyService.resetCache();
    InvoiceProductFieldCopyService.cachedDefinitions = new List<FieldCopyDefinition__c>{
      new FieldCopyDefinition__c(
        Name = 'Test_Inv_AccountName_Keep',
        SourceObject__c = 'Account',
        SourceFieldApiName__c = 'Name',
        TargetFieldApiName__c = 'Memo__c',
        TargetObject__c = 'Invoice__c'
      )
    };

    Invoice__c invoice = new Invoice__c(
      Memo__c = 'DataLoader取引先'
    );
    InvoiceProductFieldCopyService.applyCopies(
      invoice,
      InvoiceProductFieldCopyService.TARGET_INVOICE,
      new Map<String, SObject>{
        'Account' => new Account(Name = 'マスタ取引先')
      }
    );
    System.assertEquals(
      'DataLoader取引先',
      invoice.Memo__c,
      '仕様: Core 第11.4.2節 既存値はコピー定義で上書きしない'
    );
  }

  @IsTest
  static void applyCopies_toInvoiceLine_copiesSampleProductCode() {
    InvoiceProductFieldCopyService.resetCache();
    InvoiceProductFieldCopyService.cachedDefinitions = new List<FieldCopyDefinition__c>{
      new FieldCopyDefinition__c(
        Name = 'Test_Line_ProductCode',
        SourceObject__c = 'Product2',
        SourceFieldApiName__c = 'ProductCode',
        TargetFieldApiName__c = 'ProductCodeSnapShot__c',
        TargetObject__c = 'InvoiceLine__c'
      )
    };

    InvoiceLine__c line = new InvoiceLine__c();
    Test.startTest();
    InvoiceProductFieldCopyService.applyCopies(
      line,
      InvoiceProductFieldCopyService.TARGET_INVOICE_LINE,
      new Map<String, SObject>{
        'Product2' => new Product2(Name = '商品', ProductCode = 'SKU-1')
      }
    );
    Test.stopTest();

    System.assertEquals(
      'SKU-1',
      line.ProductCodeSnapShot__c,
      '仕様: Core 第11.4.2節 請求明細見本は商品コードを商品コード SnapShot へコピーする'
    );
  }

  @IsTest
  static void applyCopies_toPeriodLine_ignoresInvoiceTargetDefinitions() {
    InvoiceProductFieldCopyService.resetCache();
    InvoiceProductFieldCopyService.cachedDefinitions = new List<FieldCopyDefinition__c>{
      new FieldCopyDefinition__c(
        Name = 'Test_Inv_Only',
        SourceObject__c = 'Account',
        SourceFieldApiName__c = 'Name',
        TargetFieldApiName__c = 'Memo__c',
        TargetObject__c = 'Invoice__c'
      )
    };

    InvoiceProduct__c periodLine = new InvoiceProduct__c();
    InvoiceProductFieldCopyService.applyCopies(
      periodLine,
      InvoiceProductFieldCopyService.TARGET_INVOICE_PRODUCT,
      new Map<String, SObject>{
        'Account' => new Account(Name = '期間明細取引先'),
        'BillingAccount__c' => new BillingAccount__c(
          BillingAddressee__c = '無視される'
        )
      }
    );

    System.assertEquals(null, periodLine.Amount__c);
    System.assertEquals(
      null,
      periodLine.Unit__c,
      '仕様: Core 第11.4.2節 Toオブジェクトが異なる定義は適用しない'
    );
  }

  @IsTest
  static void validateActiveDefinitions_rejectsHardcodedTargetOverlap() {
    InvoiceProductFieldCopyService.resetCache();
    InvoiceProductFieldCopyService.cachedDefinitions = new List<FieldCopyDefinition__c>{
      new FieldCopyDefinition__c(
        Name = 'Bad_Overlap_Addressee',
        SourceObject__c = 'BillingAccount__c',
        SourceFieldApiName__c = 'BillingAddressee__c',
        TargetFieldApiName__c = 'BillingAddresseeSnapShot__c',
        TargetObject__c = 'Invoice__c'
      )
    };
    Boolean rejected = false;
    try {
      InvoiceProductFieldCopyService.validateActiveDefinitions();
    } catch (InvoiceProductFieldCopyService.FieldCopyException ex) {
      rejected = true;
      System.assertEquals(
        '請求項目コピー「Bad_Overlap_Addressee」のコピー先項目「BillingAddresseeSnapShot__c」はパッケージ標準（ハードコード）と重複しています。必須項目はコード側、顧客拡張だけをコピー定義に置いてください。',
        ex.getMessage(),
        '仕様: Core 第11.4.2節 ハードコード先とTargetFieldApiNameが重複したらエラー'
      );
    }
    System.assertEquals(true, rejected);
  }

  @IsTest
  static void validateActiveDefinitions_doesNotThrowForSeededRecords() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      InvoiceProductFieldCopyService.resetCache();
      FieldCopyDefinitionService.resetCache();
      InvoiceProductFieldCopyService.cachedDefinitions = new List<FieldCopyDefinition__c>{
        new FieldCopyDefinition__c(
          Name = 'Ok_Inv_AccountName',
          SourceObject__c = 'Account',
          SourceFieldApiName__c = 'Name',
          TargetFieldApiName__c = 'Memo__c',
          TargetObject__c = 'Invoice__c'
        )
      };
      Test.startTest();
      InvoiceProductFieldCopyService.validateActiveDefinitions();
      InvoiceProductFieldCopyService.resetCache();
      FieldCopyDefinitionService.resetCache();
      FieldCopyDefinitionService.validateAllDefinitions();
      Test.stopTest();
    }
  }

  @IsTest
  static void helpers_coverFieldNameAndQueryPaths() {
    InvoiceProductFieldCopyService.resetCache();
    System.assertEquals(
      true,
      InvoiceProductFieldCopyService.getHardcodedTargetFieldApiNames(
          InvoiceProductFieldCopyService.TARGET_INVOICE
        )
        .contains('BillingAddresseeSnapShot__c'),
      '仕様: Core 第11.4.2節 宛名 SnapShot はハードコード先。コピー定義の To に置けない'
    );
    System.assertEquals(
      true,
      InvoiceProductFieldCopyService.getSourceFieldApiNames(
          InvoiceProductFieldCopyService.OBJECT_ACCOUNT,
          InvoiceProductFieldCopyService.TARGET_INVOICE
        )
        .contains('Name'),
      '仕様: Core 第11.4.2節 請求の見本は取引先名をメモへ'
    );
    System.assertEquals(
      true,
      InvoiceProductFieldCopyService.getTargetFieldApiNames(
          InvoiceProductFieldCopyService.TARGET_INVOICE
        )
        .contains('Memo__c'),
      '仕様: Core 第11.4.2節 請求の見本は取引先名をメモへ'
    );
    System.assertEquals(
      true,
      InvoiceProductFieldCopyService.getTargetFieldApiNames().contains('Memo__c'),
      '仕様: Core 第11.4.2節 請求の見本は取引先名をメモへ'
    );
    System.assertEquals(
      InvoiceProductFieldCopyService.PATH_BILLING_ACCOUNT,
      InvoiceProductFieldCopyService.relationPathLabel(
        InvoiceProductFieldCopyService.OBJECT_BILLING_ACCOUNT
      ),
      '仕様: Core 第11.4.2節 届かない相手の経路を人が見る文に出す'
    );

    Account coverAccount = ContractTestDataFactory.insertAccount('query-cover');
    BillingAccount__c ba = new BillingAccount__c(
      Account__c = coverAccount.Id,
      BillingAddressee__c = 'query-cover',
      BillingEmailTo__c = 'query@example.com',
      InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER,
      InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY,
      InvoiceDateDayOfMonth__c = 1,
      InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
      PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET,
      PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END,
      PaymentTermMonthOffset__c = 0,
      PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE);
    ContractTestDataFactory.applyRequiredFields(ba);
    insert ba;

    SObject loaded = InvoiceProductFieldCopyService.querySourceRecord(
      InvoiceProductFieldCopyService.OBJECT_BILLING_ACCOUNT,
      ba.Id
    );
    System.assertEquals(
      ba.Id,
      loaded.Id,
      '仕様: Core 第11.4.2節 コピー元の請求アカウントを読む'
    );

    InvoiceProduct__c periodLine = new InvoiceProduct__c();
    InvoiceProductFieldCopyService.applyCopies(
      periodLine,
      new Map<String, SObject>{
        InvoiceProductFieldCopyService.OBJECT_CONTRACT_PRODUCT => new ContractProduct__c(
          Unit__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT
        ),
        InvoiceProductFieldCopyService.OBJECT_BILLING_ACCOUNT => ba,
        InvoiceProductFieldCopyService.OBJECT_CONTRACT_HISTORY => new ContractHistory__c(),
        InvoiceProductFieldCopyService.OBJECT_PRODUCT => new Product2(
          Name = 'p'
        ),
        InvoiceProductFieldCopyService.OBJECT_OPPORTUNITY => new Opportunity(
          Name = 'o',
          CloseDate = Date.today()
        ),
        InvoiceProductFieldCopyService.OBJECT_ACCOUNT => new Account(Name = 'a')
      }
    );
    System.assertEquals(null, periodLine.Amount__c);
  }

  @IsTest
  static void areTypesCompatible_coversCommonPairs() {
    System.assertEquals(
      true,
      InvoiceProductFieldCopyService.areTypesCompatible(
        Schema.DisplayType.STRING,
        Schema.DisplayType.TEXTAREA
      )
    );
    System.assertEquals(
      true,
      InvoiceProductFieldCopyService.areTypesCompatible(
        Schema.DisplayType.DOUBLE,
        Schema.DisplayType.CURRENCY
      )
    );
    System.assertEquals(
      true,
      InvoiceProductFieldCopyService.areTypesCompatible(
        Schema.DisplayType.REFERENCE,
        Schema.DisplayType.ID
      )
    );
    System.assertEquals(
      true,
      InvoiceProductFieldCopyService.areTypesCompatible(
        Schema.DisplayType.DATE,
        Schema.DisplayType.DATETIME
      )
    );
    System.assertEquals(
      false,
      InvoiceProductFieldCopyService.areTypesCompatible(
        Schema.DisplayType.STRING,
        Schema.DisplayType.DATE
      )
    );
    System.assertEquals(
      false,
      InvoiceProductFieldCopyService.areTypesCompatible(
        null,
        Schema.DisplayType.STRING
      )
    );
    System.assertEquals(
      InvoiceProductFieldCopyService.PATH_CONTRACT_HISTORY,
      InvoiceProductFieldCopyService.relationPathLabel(
        InvoiceProductFieldCopyService.OBJECT_CONTRACT_HISTORY
      )
    );
    System.assertEquals(
      InvoiceProductFieldCopyService.PATH_CONTRACT_PRODUCT,
      InvoiceProductFieldCopyService.relationPathLabel(
        InvoiceProductFieldCopyService.OBJECT_CONTRACT_PRODUCT
      )
    );
    System.assertEquals(
      InvoiceProductFieldCopyService.PATH_PRODUCT,
      InvoiceProductFieldCopyService.relationPathLabel(
        InvoiceProductFieldCopyService.OBJECT_PRODUCT
      )
    );
    System.assertEquals(
      InvoiceProductFieldCopyService.PATH_OPPORTUNITY,
      InvoiceProductFieldCopyService.relationPathLabel(
        InvoiceProductFieldCopyService.OBJECT_OPPORTUNITY
      )
    );
    System.assertEquals(
      InvoiceProductFieldCopyService.PATH_ACCOUNT,
      InvoiceProductFieldCopyService.relationPathLabel(
        InvoiceProductFieldCopyService.OBJECT_ACCOUNT
      )
    );
    System.assertEquals(
      'Other__c',
      InvoiceProductFieldCopyService.relationPathLabel('Other__c')
    );
    System.assertEquals(
      null,
      InvoiceProductFieldCopyService.querySourceRecord(
        InvoiceProductFieldCopyService.OBJECT_BILLING_ACCOUNT,
        null
      )
    );
    System.assertEquals(
      new Set<String>{ 'Id' },
      InvoiceProductFieldCopyService.getSourceFieldApiNames('NotAllowed__c')
    );
  }

  @IsTest
  static void applyCopies_andValidate_coverErrorAndCoercePaths() {
    InvoiceProductFieldCopyService.resetCache();
    InvoiceProductFieldCopyService.cachedDefinitions = new List<FieldCopyDefinition__c>{
      new FieldCopyDefinition__c(
        Name = 'Test_Account_Coerce',
        SourceObject__c = 'Account',
        SourceFieldApiName__c = 'Name',
        TargetFieldApiName__c = 'Memo__c',
        TargetObject__c = 'Invoice__c'
      )
    };

    Invoice__c invoice = new Invoice__c();
    InvoiceProductFieldCopyService.applyCopies(
      invoice,
      InvoiceProductFieldCopyService.TARGET_INVOICE,
      new Map<String, SObject>{
        'Account' => new Account(Name = 'coerce-account')
      }
    );
    System.assertEquals('coerce-account', invoice.Memo__c);

    Boolean missingSource = false;
    try {
      InvoiceProductFieldCopyService.applyCopies(
        new Invoice__c(),
        InvoiceProductFieldCopyService.TARGET_INVOICE,
        new Map<String, SObject>()
      );
    } catch (InvoiceProductFieldCopyService.FieldCopyException ex) {
      missingSource = true;
      System.assertEquals(
        '請求項目コピー「Test_Account_Coerce」のコピー元「Account」の参照先が見つかりません（請求商品 → 契約履歴 → 契約サービス → 取引先）。',
        ex.getMessage(),
        '仕様: Core 第11.4.2節 届かない相手へ空埋めしない。定義が壊れていたら止める'
      );
    }
    System.assertEquals(true, missingSource);

    Invoice__c skipped = new Invoice__c();
    InvoiceProductFieldCopyService.applyCopies(
      skipped,
      InvoiceProductFieldCopyService.TARGET_INVOICE,
      new Map<String, SObject>(),
      true
    );
    System.assertEquals(
      null,
      skipped.Memo__c,
      '仕様: Core 第11.4.2節 届かない相手へ空埋めしない'
    );

    InvoiceProductFieldCopyService.cachedDefinitions = new List<FieldCopyDefinition__c>{
      new FieldCopyDefinition__c(
        Name = 'Bad_Incomplete',
        SourceObject__c = null,
        SourceFieldApiName__c = null,
        TargetFieldApiName__c = null,
        TargetObject__c = 'Invoice__c'
      )
    };
    Boolean incomplete = false;
    try {
      InvoiceProductFieldCopyService.validateActiveDefinitions();
    } catch (InvoiceProductFieldCopyService.FieldCopyException ex) {
      incomplete = true;
      System.assertEquals(
        '請求項目コピー「Bad_Incomplete」の設定が不完全です（Fromオブジェクト / From項目API名 / To項目API名は必須です）。',
        ex.getMessage()
      );
    }
    System.assertEquals(true, incomplete);

    InvoiceProductFieldCopyService.cachedDefinitions = new List<FieldCopyDefinition__c>{
      new FieldCopyDefinition__c(
        Name = 'Bad_SourceObject',
        SourceObject__c = 'NotAnObject__c',
        SourceFieldApiName__c = 'Name',
        TargetFieldApiName__c = 'Memo__c',
        TargetObject__c = 'Invoice__c'
      )
    };
    Boolean badSource = false;
    try {
      InvoiceProductFieldCopyService.validateActiveDefinitions();
    } catch (InvoiceProductFieldCopyService.FieldCopyException ex) {
      badSource = true;
      System.assertEquals(
        '請求項目コピー「Bad_SourceObject」のコピー元オブジェクト「NotAnObject__c」は許可されていません。',
        ex.getMessage()
      );
    }
    System.assertEquals(true, badSource);

    InvoiceProductFieldCopyService.cachedDefinitions = new List<FieldCopyDefinition__c>{
      new FieldCopyDefinition__c(
        Name = 'Bad_TargetField',
        SourceObject__c = 'Account',
        SourceFieldApiName__c = 'Name',
        TargetFieldApiName__c = 'DoesNotExist__c',
        TargetObject__c = 'Invoice__c'
      )
    };
    Boolean badTarget = false;
    try {
      InvoiceProductFieldCopyService.validateActiveDefinitions();
    } catch (InvoiceProductFieldCopyService.FieldCopyException ex) {
      badTarget = true;
      System.assertEquals(
        '請求項目コピー「Bad_TargetField」のコピー先項目「DoesNotExist__c」が「Invoice__c」に存在しません。',
        ex.getMessage()
      );
    }
    System.assertEquals(true, badTarget);

    InvoiceProductFieldCopyService.resetCache();
    System.assert(
      !InvoiceProductFieldCopyService.getActiveDefinitions().isEmpty()
    );
  }

  @IsTest
  static void applyOnBeforeInsert_andHardcodedSnapshot_coverBlankOnly() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      InvoiceProductFieldCopyService.applyOnBeforeInsert(
        new List<Invoice__c>(),
        InvoiceProductFieldCopyService.TARGET_INVOICE
      );
      InvoiceProductFieldCopyService.applyOnBeforeInsert(
        new List<Invoice__c>{ new Invoice__c() },
        null
      );
      InvoiceProductFieldCopyService.applyOnBeforeInsert(
        new List<InvoiceProduct__c>{ new InvoiceProduct__c() },
        InvoiceProductFieldCopyService.TARGET_INVOICE_PRODUCT
      );
      InvoiceProductFieldCopyService.applyOnBeforeInsert(
        new List<InvoiceLine__c>{ new InvoiceLine__c() },
        InvoiceProductFieldCopyService.TARGET_INVOICE_LINE
      );
      InvoiceProductFieldCopyService.applyOnBeforeInsert(
        new List<Invoice__c>{ new Invoice__c() },
        InvoiceProductFieldCopyService.TARGET_INVOICE
      );

      InvoiceProductFieldCopyService.cachedDefinitions = new List<FieldCopyDefinition__c>{
        new FieldCopyDefinition__c(
          Name = 'Bad_Missing_Object',
          SourceObject__c = 'Account',
          SourceFieldApiName__c = 'Name',
          TargetFieldApiName__c = 'Memo__c',
          TargetObject__c = 'DoesNotExist__c'
        )
      };
      Boolean missingTarget = false;
      try {
        InvoiceProductFieldCopyService.validateActiveDefinitions();
      } catch (InvoiceProductFieldCopyService.FieldCopyException ex) {
        missingTarget = true;
        System.assertEquals(
          '請求項目コピー「Bad_Missing_Object」のコピー先オブジェクト「DoesNotExist__c」が組織に存在しません。',
          ex.getMessage(),
          '仕様: Core 第11.4.2節 無いToオブジェクトは設定エラー'
        );
      }
      System.assertEquals(true, missingTarget);
      InvoiceProductFieldCopyService.resetCache();

      Account account = ContractTestDataFactory.insertAccount('copy-insert-src');
      BillingAccount__c billingAccount = ContractTestDataFactory.insertBillingAccount(
        account.Id
      );
      ContractService__c service = new ContractService__c(
        Name = 'copy-insert-src サービス',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id,
        TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
      );
      ContractTestDataFactory.applyRequiredFields(service);
      insert service;
      ContractHistory__c history = new ContractHistory__c(
        Name = 'COPY-INS-H',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1
      );
      ContractTestDataFactory.applyRequiredFields(history);
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        history,
        account.Id
      );
      insert history;
      Product2 product = ContractTestDataFactory.buildProduct(
        'copy-insert-src Prod'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      ContractTestDataFactory.insertProduct(product);
      ContractProduct__c contractProduct = new ContractProduct__c(
        ContractHistory__c = history.Id,
        Account__c = account.Id,
        Product__c = product.Id,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME,
        Type__c = 'New',
        Quantity__c = 1,
        UnitPrice__c = 1000,
        Amount__c = 1000,
        StartDate__c = Date.today(),
        Enddate__c = Date.today(),
        RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME
      );
      ContractTestDataFactory.applyRequiredFields(contractProduct);
      contractProduct.Amount__c = 1000;
      insert contractProduct;

      Invoice__c invoiceDraft = new Invoice__c(
        ContractHistory__c = history.Id,
        ContractService__c = service.Id,
        BillingAccountSnapShot__c = billingAccount.Id
      );
      InvoiceProductFieldCopyService.applyOnBeforeInsert(
        new List<Invoice__c>{ invoiceDraft },
        InvoiceProductFieldCopyService.TARGET_INVOICE
      );
      System.assertEquals(
        billingAccount.BillingAddressee__c,
        invoiceDraft.BillingAddresseeSnapShot__c,
        '仕様: Core 第11.4.2節 空欄だけコピーする'
      );
      InvoiceLine__c lineDraft = new InvoiceLine__c(
        ContractProduct__c = contractProduct.Id
      );
      InvoiceProductFieldCopyService.applyOnBeforeInsert(
        new List<InvoiceLine__c>{ lineDraft },
        InvoiceProductFieldCopyService.TARGET_INVOICE_LINE
      );
      System.assertEquals(
        product.Id,
        lineDraft.Product__c,
        '仕様: Core 第11.4.2節 空欄の商品参照をコピーする'
      );
      System.assertEquals(
        contractProduct.Unit__c,
        lineDraft.Unit__c,
        '仕様: Core 第11.4.2節 空欄の単位をコピーする'
      );
      InvoiceLine__c populatedLine = new InvoiceLine__c(
        Product__c = product.Id,
        Unit__c = '既存単位'
      );
      InvoiceProductFieldCopyService.applyHardcodedInvoiceLineProductFields(
        populatedLine,
        new ContractProduct__c(
          Product__c = null,
          Unit__c = contractProduct.Unit__c
        )
      );
      System.assertEquals(
        product.Id,
        populatedLine.Product__c,
        '仕様: Core 第11.4.2節 請求明細の商品参照に既存値があれば上書きしない'
      );
      System.assertEquals(
        '既存単位',
        populatedLine.Unit__c,
        '仕様: Core 第11.4.2節 請求明細の単位に既存値があれば上書きしない'
      );
      InvoiceProductFieldCopyService.applyOnBeforeInsert(
        new List<InvoiceProduct__c>{
          new InvoiceProduct__c(
            ContractProduct__c = contractProduct.Id,
            ContractHistory__c = history.Id
          )
        },
        InvoiceProductFieldCopyService.TARGET_INVOICE_PRODUCT
      );
      InvoiceProductFieldCopyService.applyHardcodedInvoiceLineProductFields(
        new InvoiceLine__c(),
        contractProduct
      );
      System.assertEquals(
        false,
        InvoiceProductFieldCopyService.isBlankTargetValue(0)
      );
      Invoice__c invoice = new Invoice__c();
      BillingAccount__c billing = new BillingAccount__c(
        BillingAddressee__c = 'コピー宛名',
        BillingEmailTo__c = 'copy@example.com'
      );
      InvoiceProductFieldCopyService.applyHardcodedInvoiceBillingAccountSnapshot(
        invoice,
        billing
      );
      System.assertEquals(
        'コピー宛名',
        invoice.BillingAddresseeSnapShot__c,
        'Core 第11.4.2節: 空欄だけコピーする'
      );
      System.assertEquals(
        'copy@example.com',
        invoice.BillingEmailToSnapShot__c,
        '仕様: Core 第3.3.5節・第3.3.7節 請求作成時の空欄へ送付先メールをスナップショットする'
      );
      invoice.BillingAddresseeSnapShot__c = '手入力';
      InvoiceProductFieldCopyService.applyHardcodedInvoiceBillingAccountSnapshot(
        invoice,
        billing
      );
      System.assertEquals(
        '手入力',
        invoice.BillingAddresseeSnapShot__c,
        'Core 第11.4.2節: 既にあれば上書きしない'
      );
    }
  }

  @IsTest
  static void rememberRecords_nullQueriedFields_coverInsertSourceWithoutReselect() {
    ContractTestDataFactory.initTestContext();
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account acc = ContractTestDataFactory.insertAccount('BA Cover');
      BillingAccount__c billing = ContractTestDataFactory.insertBillingAccount(
        acc.Id
      );
      InvoiceProductFieldCopyService.resetCache();
      Set<String> queried = InvoiceProductFieldCopyService.getSourceFieldApiNames(
        InvoiceProductFieldCopyService.OBJECT_BILLING_ACCOUNT
      );
      queried.add('BillingEmailTo__c');
      queried.add('BillingAccountKey__c');
      Map<String, Schema.SObjectField> fieldMap = BillingAccount__c.SObjectType.getDescribe()
        .fields.getMap();
      List<String> selectList = new List<String>();
      for (String fieldApiName : queried) {
        if (fieldMap.containsKey(fieldApiName)) {
          selectList.add(fieldApiName);
        }
      }
      Id billingId = billing.Id;
      BillingAccount__c loaded = (BillingAccount__c) Database.query(
        'SELECT ' +
          String.join(selectList, ',') +
          ' FROM BillingAccount__c WHERE Id = :billingId WITH SYSTEM_MODE'
      );
      InvoiceProductFieldCopyService.rememberRecords(
        new List<SObject>{ loaded },
        new Set<String>(selectList)
      );
      Integer beforeQueries = Limits.getQueries();
      InvoiceProductFieldCopyService.querySourceRecord(
        InvoiceProductFieldCopyService.OBJECT_BILLING_ACCOUNT,
        loaded.Id
      );
      System.assertEquals(
        beforeQueries,
        Limits.getQueries(),
        '仕様: Core 第11.4.2節・第6.1節。SELECTした請求アカウント（null含む）をInsertで再SOQLしない'
      );
    }
  }

  @IsTest
  static void querySourceRecord_contractHistory_selectsContractServiceRelation() {
    ContractTestDataFactory.initTestContext();
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('Copy History Acc');
      BillingAccount__c billing = ContractTestDataFactory.insertBillingAccount(
        account.Id
      );
      ContractService__c service = new ContractService__c(
        Name = 'Copy History Service',
        Account__c = account.Id,
        BiilingAcccount__c = billing.Id,
        TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
      );
      ContractTestDataFactory.applyRequiredFields(service);
      insert service;
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Copy History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2026, 6, 30),
        EffectiveDate__c = Date.newInstance(2026, 6, 1)
      );
      ContractTestDataFactory.applyRequiredFields(history);
      ContractTestDataFactory.applyEstimateOrderedOpportunity(history, account.Id);
      insert history;
      InvoiceProductFieldCopyService.resetCache();
      SObject loaded = InvoiceProductFieldCopyService.querySourceRecord(
        InvoiceProductFieldCopyService.OBJECT_CONTRACT_HISTORY,
        history.Id
      );
      System.assertNotEquals(null, loaded, '契約履歴を読む');
      SObject related = loaded.getSObject('ContractService__r');
      System.assertNotEquals(
        null,
        related,
        '仕様: Core 第11.4.2節。契約履歴のコピー元はContractService__rをSELECTする'
      );
      System.assertEquals(service.Id, related.Id);
    }
  }

  @IsTest
  static void querySourceRecord_contractService_doesNotReuseThinCache() {
    ContractTestDataFactory.initTestContext();
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('Thin Service Acc');
      BillingAccount__c billing = ContractTestDataFactory.insertBillingAccount(
        account.Id
      );
      ContractService__c service = new ContractService__c(
        Name = 'Thin Service Name',
        Account__c = account.Id,
        BiilingAcccount__c = billing.Id,
        TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
      );
      ContractTestDataFactory.applyRequiredFields(service);
      insert service;
      insert new FieldCopyDefinition__c(
        Name = 'Test_Thin_Service_Name',
        TargetObject__c = 'ContractHistory__c',
        Context__c = FieldCopyDefinitionService.CONTEXT_AUTO_RENEW,
        SourceObject__c = InvoiceProductFieldCopyService.OBJECT_CONTRACT_SERVICE,
        SourceFieldApiName__c = 'Name',
        TargetFieldApiName__c = 'Note__c'
      );
      InvoiceProductFieldCopyService.resetCache();
      ContractService__c thin = [
        SELECT Id, TaxPercent__c, Account__c, BiilingAcccount__c
        FROM ContractService__c
        WHERE Id = :service.Id
      ];
      InvoiceProductFieldCopyService.rememberRecords(
        new List<SObject>{ thin }
      );
      SObject loaded = InvoiceProductFieldCopyService.querySourceRecord(
        InvoiceProductFieldCopyService.OBJECT_CONTRACT_SERVICE,
        service.Id
      );
      System.assertEquals(
        'Thin Service Name',
        (String) loaded.get('Name'),
        '仕様: Core 第11.4.2節。薄い契約サービスキャッシュではFromを読まない'
      );
    }
  }
}
