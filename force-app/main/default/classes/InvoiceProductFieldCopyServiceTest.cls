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
    Set<String> invoiceTargets = new Set<String>();
    for (
      FieldCopyDefinition__c definition : InvoiceProductFieldCopyService.getActiveDefinitions(
        InvoiceProductFieldCopyService.TARGET_INVOICE
      )
    ) {
      invoiceTargets.add(definition.TargetFieldApiName__c);
    }
    Set<String> lineTargets = new Set<String>();
    for (
      FieldCopyDefinition__c definition : InvoiceProductFieldCopyService.getActiveDefinitions(
        InvoiceProductFieldCopyService.TARGET_INVOICE_LINE
      )
    ) {
      lineTargets.add(definition.TargetFieldApiName__c);
    }
    Set<String> periodTargets = new Set<String>();
    for (
      FieldCopyDefinition__c definition : InvoiceProductFieldCopyService.getActiveDefinitions(
        InvoiceProductFieldCopyService.TARGET_INVOICE_PRODUCT
      )
    ) {
      periodTargets.add(definition.TargetFieldApiName__c);
    }

    System.assert(
      invoiceTargets.contains('Memo__c'),
      '仕様: Core 第11.4.2節 Sample_Inv_AccountName'
    );
    System.assert(
      lineTargets.contains('ProductCodeSnapShot__c'),
      '仕様: Core 第11.4.2節 Sample_Line_ProductCode'
    );
    System.assertEquals(
      true,
      periodTargets.isEmpty(),
      '期間明細向け寄せ項目サンプルは置かない'
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

    System.assertEquals('サンプル取引先', invoice.Memo__c);
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
    System.assertEquals('DataLoader取引先', invoice.Memo__c);
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

    System.assertEquals('SKU-1', line.ProductCodeSnapShot__c);
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
      System.assert(ex.getMessage().contains('ハードコード'), ex.getMessage());
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
    System.assert(
      !InvoiceProductFieldCopyService.getHardcodedTargetFieldApiNames(
          InvoiceProductFieldCopyService.TARGET_INVOICE
        )
        .isEmpty()
    );
    System.assert(
      !InvoiceProductFieldCopyService.getSourceFieldApiNames(
          InvoiceProductFieldCopyService.OBJECT_ACCOUNT,
          InvoiceProductFieldCopyService.TARGET_INVOICE
        )
        .isEmpty()
    );
    System.assert(
      !InvoiceProductFieldCopyService.getTargetFieldApiNames(
          InvoiceProductFieldCopyService.TARGET_INVOICE
        )
        .isEmpty()
    );
    System.assert(
      !InvoiceProductFieldCopyService.getTargetFieldApiNames().isEmpty()
    );
    System.assertEquals(
      InvoiceProductFieldCopyService.TARGET_INVOICE_PRODUCT,
      InvoiceProductFieldCopyService.resolveTargetObject(null)
    );
    System.assert(
      String.isNotBlank(
        InvoiceProductFieldCopyService.relationPathLabel(
          InvoiceProductFieldCopyService.OBJECT_BILLING_ACCOUNT
        )
      )
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
    System.assertNotEquals(null, loaded);

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
          StageName = 'Prospecting',
          CloseDate = Date.today()
        ),
        InvoiceProductFieldCopyService.OBJECT_ACCOUNT => new Account(Name = 'a')
      }
    );
    System.assertEquals(null, periodLine.Amount__c);
  }

  @IsTest
  static void applyCopies_blankTargetDefaultsToInvoiceProduct() {
    InvoiceProductFieldCopyService.resetCache();
    InvoiceProductFieldCopyService.cachedDefinitions = new List<FieldCopyDefinition__c>{
      new FieldCopyDefinition__c(
        Name = 'Test_Blank_Target',
        SourceObject__c = 'Account',
        SourceFieldApiName__c = 'Name',
        TargetFieldApiName__c = 'Memo__c',
        TargetObject__c = InvoiceProductFieldCopyService.TARGET_INVOICE
      )
    };
    Invoice__c invoice = new Invoice__c();
    InvoiceProductFieldCopyService.applyCopies(
      invoice,
      InvoiceProductFieldCopyService.TARGET_INVOICE,
      new Map<String, SObject>{
        'Account' => new Account(Name = 'デフォルト先')
      }
    );
    System.assertEquals('デフォルト先', invoice.Memo__c);
    System.assertEquals(
      InvoiceProductFieldCopyService.TARGET_INVOICE_PRODUCT,
      InvoiceProductFieldCopyService.resolveTargetObject(null)
    );
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
    }
    System.assertEquals(true, missingSource);

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
        missingTarget = ex.getMessage().contains('存在しません');
      }
      System.assertEquals(
        true,
        missingTarget,
        'Core 第11.4.2節: 無いToオブジェクトは設定エラー'
      );
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

      InvoiceProductFieldCopyService.applyOnBeforeInsert(
        new List<Invoice__c>{
          new Invoice__c(
            ContractHistory__c = history.Id,
            ContractService__c = service.Id,
            BillingAccountSnapShot__c = billingAccount.Id
          )
        },
        InvoiceProductFieldCopyService.TARGET_INVOICE
      );
      InvoiceProductFieldCopyService.applyOnBeforeInsert(
        new List<InvoiceLine__c>{
          new InvoiceLine__c(ContractProduct__c = contractProduct.Id)
        },
        InvoiceProductFieldCopyService.TARGET_INVOICE_LINE
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
}
