@IsTest
private class InvoiceFieldCopyTriggerHandlerTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
    ContractTestDataFactory.ensureOrgAccountingPolicy();
  }

  @IsTest
  static void invoiceBeforeInsert_fillsBlankBillingSnapshots() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('Fill');
      Invoice__c invoice = new Invoice__c(
        ContractHistory__c = fixture.history.Id,
        ContractService__c = fixture.service.Id,
        InvoiceDate__c = Date.today(),
        Amount__c = 1000
      );
      ContractTestDataFactory.applyInvoiceInsertSeedStatuses(invoice);

      Test.startTest();
      insert invoice;
      Test.stopTest();

      Invoice__c loaded = [
        SELECT
          BillingAccountSnapShot__c,
          BillingAddresseeSnapShot__c,
          BillingEmailToSnapShot__c,
          BillingEmailCcSnapShot__c,
          BillingEmailBccSnapShot__c,
          InvoiceDeliveryMethodSnapShot__c,
          PaymentTermMethodSnapShot__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(
        fixture.billingAccount.Id,
        loaded.BillingAccountSnapShot__c,
        '仕様: Core 第11.4.2節・第5.2節 空欄だけコピーする。請求アカウント参照をスナップショットする'
      );
      System.assertEquals(
        'トリガ宛名 御中',
        loaded.BillingAddresseeSnapShot__c,
        '仕様: Core 第11.4.2節・第5.2節 空欄だけコピーする。宛名をスナップショットする'
      );
      System.assertEquals(
        'trig@example.com',
        loaded.BillingEmailToSnapShot__c,
        '仕様: Core 第11.4.2節・第5.2節 空欄だけコピーする。送付先メール To をスナップショットする'
      );
      System.assertEquals(
        'trig-cc@example.com',
        loaded.BillingEmailCcSnapShot__c,
        '仕様: Core 第11.4.2節・第5.2節 空欄だけコピーする。送付先メール Cc をスナップショットする'
      );
      System.assertEquals(
        'trig-bcc@example.com',
        loaded.BillingEmailBccSnapShot__c,
        '仕様: Core 第11.4.2節・第5.2節 空欄だけコピーする。送付先メール Bcc をスナップショットする'
      );
      System.assertEquals(
        InvoiceDeliveryMethodService.EMAIL,
        loaded.InvoiceDeliveryMethodSnapShot__c,
        '仕様: Core 第11.4.2節・第5.2節・第3.3.7節 空欄だけコピーする。届け方をスナップショットする'
      );
      System.assertEquals(
        BillingScheduleService.METHOD_MONTH_OFFSET,
        loaded.PaymentTermMethodSnapShot__c,
        '仕様: Core 第11.4.2節・第5.2節・第7.5節 空欄だけコピーする。支払条件をスナップショットする'
      );
    }
  }

  @IsTest
  static void invoiceBeforeInsert_keepsPrefilledSnapshot() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('Keep');
      Invoice__c invoice = new Invoice__c(
        ContractHistory__c = fixture.history.Id,
        ContractService__c = fixture.service.Id,
        InvoiceDate__c = Date.today(),
        Amount__c = 1000,
        BillingAddresseeSnapShot__c = '手入力宛名'
      );
      ContractTestDataFactory.applyInvoiceInsertSeedStatuses(invoice);

      Test.startTest();
      insert invoice;
      Test.stopTest();

      Invoice__c loaded = [
        SELECT
          BillingAddresseeSnapShot__c,
          BillingEmailToSnapShot__c,
          BillingAccountSnapShot__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(
        '手入力宛名',
        loaded.BillingAddresseeSnapShot__c,
        '仕様: Core 第11.4.2節 既にあれば上書きしない'
      );
      System.assertEquals(
        'trig@example.com',
        loaded.BillingEmailToSnapShot__c,
        '仕様: Core 第11.4.2節・第5.2節 空欄だけコピーする。送付先メール To をスナップショットする'
      );
      System.assertEquals(
        fixture.billingAccount.Id,
        loaded.BillingAccountSnapShot__c,
        '仕様: Core 第11.4.2節・第5.2節 空欄だけコピーする。請求アカウント参照をスナップショットする'
      );
    }
  }

  @IsTest
  static void invoiceBeforeInsert_copiesBlankMemoFromAccount() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('CopyMemo');
      insert new FieldCopyDefinition__c(
        Name = 'Test_Inv_Memo_From_Account',
        TargetObject__c = InvoiceProductFieldCopyService.TARGET_INVOICE,
        SourceObject__c = InvoiceProductFieldCopyService.OBJECT_ACCOUNT,
        SourceFieldApiName__c = 'Name',
        TargetFieldApiName__c = 'Memo__c'
      );
      InvoiceProductFieldCopyService.resetCache();
      FieldCopyDefinitionService.resetCache();
      Invoice__c invoice = new Invoice__c(
        ContractHistory__c = fixture.history.Id,
        ContractService__c = fixture.service.Id,
        InvoiceDate__c = Date.today(),
        Amount__c = 1000
      );
      ContractTestDataFactory.applyInvoiceInsertSeedStatuses(invoice);

      Test.startTest();
      insert invoice;
      Test.stopTest();

      Invoice__c loaded = [SELECT Memo__c FROM Invoice__c WHERE Id = :invoice.Id];
      System.assertEquals(
        'FieldCopy CopyMemo Acc',
        loaded.Memo__c,
        '仕様: Core 第11.4.2節 請求系はinsert時だけ空欄へスタンプする。From＝取引先'
      );
    }
  }

  @IsTest
  static void invoiceBeforeInsert_copiesBlankMemoFromContractProductUnit() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('CpUnit');
      insert new FieldCopyDefinition__c(
        Name = 'Test_Inv_Memo_From_CpUnit',
        TargetObject__c = InvoiceProductFieldCopyService.TARGET_INVOICE,
        SourceObject__c = InvoiceProductFieldCopyService.OBJECT_CONTRACT_PRODUCT,
        SourceFieldApiName__c = 'Unit__c',
        TargetFieldApiName__c = 'Memo__c'
      );
      InvoiceProductFieldCopyService.resetCache();
      FieldCopyDefinitionService.resetCache();
      Invoice__c invoice = new Invoice__c(
        ContractHistory__c = fixture.history.Id,
        ContractService__c = fixture.service.Id,
        InvoiceDate__c = Date.today(),
        Amount__c = 1000
      );
      ContractTestDataFactory.applyInvoiceInsertSeedStatuses(invoice);
      InvoiceProductFieldCopyService.rememberInvoiceInsertContractProducts(
        new List<Id>{ fixture.contractProduct.Id }
      );

      Test.startTest();
      insert invoice;
      Test.stopTest();

      Invoice__c loaded = [SELECT Memo__c FROM Invoice__c WHERE Id = :invoice.Id];
      System.assertEquals(
        ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT,
        loaded.Memo__c,
        '仕様: Core 第11.4.2節 請求系はinsert時だけ空欄へスタンプする。請求書の From に見積商品がある'
      );
    }
  }

  @IsTest
  static void invoiceBeforeInsert_copiesBlankMemoFromHistoryName() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('HistName');
      insert new FieldCopyDefinition__c(
        Name = 'Test_Inv_Memo_From_HistoryName',
        TargetObject__c = InvoiceProductFieldCopyService.TARGET_INVOICE,
        SourceObject__c = InvoiceProductFieldCopyService.OBJECT_CONTRACT_HISTORY,
        SourceFieldApiName__c = 'Name',
        TargetFieldApiName__c = 'Memo__c'
      );
      InvoiceProductFieldCopyService.resetCache();
      FieldCopyDefinitionService.resetCache();
      Invoice__c invoice = new Invoice__c(
        ContractHistory__c = fixture.history.Id,
        ContractService__c = fixture.service.Id,
        InvoiceDate__c = Date.today(),
        Amount__c = 1000
      );
      ContractTestDataFactory.applyInvoiceInsertSeedStatuses(invoice);

      Test.startTest();
      insert invoice;
      Test.stopTest();

      Invoice__c loaded = [SELECT Memo__c FROM Invoice__c WHERE Id = :invoice.Id];
      System.assertEquals(
        fixture.history.Name,
        loaded.Memo__c,
        '仕様: Core 第11.4.2節 請求系はinsert時だけ空欄へスタンプする。請求書の From に契約履歴がある'
      );
    }
  }

  @IsTest
  static void invoiceLineBeforeInsert_fillsBlankProductUnit() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('Line');
      Invoice__c invoice = new Invoice__c(
        ContractHistory__c = fixture.history.Id,
        ContractService__c = fixture.service.Id,
        InvoiceDate__c = Date.today(),
        Amount__c = 1000,
        BillingAccountSnapShot__c = fixture.billingAccount.Id,
        BillingAddresseeSnapShot__c = '固定宛名'
      );
      ContractTestDataFactory.applyInvoiceInsertSeedStatuses(invoice);
      insert invoice;

      InvoiceLine__c line = new InvoiceLine__c(
        Invoice__c = invoice.Id,
        ContractProduct__c = fixture.contractProduct.Id,
        ProductName__c = 'テスト商品',
        Amount__c = 1000,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        RevenueRecognitionBasis__c = '月次計上'
      );

      Test.startTest();
      insert line;
      Test.stopTest();

      InvoiceLine__c loaded = [
        SELECT Product__c, Unit__c
        FROM InvoiceLine__c
        WHERE Id = :line.Id
      ];
      System.assertEquals(
        fixture.product.Id,
        loaded.Product__c,
        '仕様: Core 第11.4.2節 空欄だけコピーする。請求明細の From に見積商品がある'
      );
      System.assertEquals(
        ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT,
        loaded.Unit__c,
        '仕様: Core 第11.4.2節 空欄だけコピーする。請求明細の From に見積商品がある'
      );
    }
  }

  @IsTest
  static void invoiceLineBeforeInsert_copiesBlankFromHistoryBillingAccountOpportunityAccount() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('LineFroms');
      Invoice__c invoice = new Invoice__c(
        ContractHistory__c = fixture.history.Id,
        ContractService__c = fixture.service.Id,
        InvoiceDate__c = Date.today(),
        Amount__c = 1000,
        BillingAccountSnapShot__c = fixture.billingAccount.Id,
        BillingAddresseeSnapShot__c = '固定宛名'
      );
      ContractTestDataFactory.applyInvoiceInsertSeedStatuses(invoice);
      insert invoice;

      InvoiceLine__c line = new InvoiceLine__c(
        Invoice__c = invoice.Id,
        ContractProduct__c = fixture.contractProduct.Id,
        ProductName__c = 'テスト商品',
        Amount__c = 1000,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        RevenueRecognitionBasis__c = '月次計上'
      );
      insert line;

      ContractHistory__c history = [
        SELECT Name, Opportunity__c, Opportunity__r.Name
        FROM ContractHistory__c
        WHERE Id = :fixture.history.Id
      ];
      ContractService__c serviceRow = [
        SELECT Account__c
        FROM ContractService__c
        WHERE Id = :fixture.service.Id
      ];
      Account account = [SELECT Name FROM Account WHERE Id = :serviceRow.Account__c];

      assertInvoiceLineBlankCopyFromSoql(
        line.Id,
        InvoiceProductFieldCopyService.OBJECT_CONTRACT_HISTORY,
        'Name',
        history.Name,
        '仕様: Core 第11.4.2節 空欄だけコピーする。請求明細の From に契約履歴がある'
      );
      assertInvoiceLineBlankCopyFromSoql(
        line.Id,
        InvoiceProductFieldCopyService.OBJECT_BILLING_ACCOUNT,
        'BillingAddressee__c',
        fixture.billingAccount.BillingAddressee__c,
        '仕様: Core 第11.4.2節 空欄だけコピーする。請求明細の From に請求アカウントがある'
      );
      assertInvoiceLineBlankCopyFromSoql(
        line.Id,
        InvoiceProductFieldCopyService.OBJECT_OPPORTUNITY,
        'Name',
        history.Opportunity__r.Name,
        '仕様: Core 第11.4.2節 空欄だけコピーする。請求明細の From に商談がある'
      );
      assertInvoiceLineBlankCopyFromSoql(
        line.Id,
        InvoiceProductFieldCopyService.OBJECT_ACCOUNT,
        'Name',
        account.Name,
        '仕様: Core 第11.4.2節 空欄だけコピーする。請求明細の From に取引先がある'
      );
    }
  }

  @IsTest
  static void periodLineBeforeInsert_keepsPrefilledAmount() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('Period');
      InvoiceProduct__c periodLine = new InvoiceProduct__c(
        ContractHistory__c = fixture.history.Id,
        ContractProduct__c = fixture.contractProduct.Id,
        StartDate__c = Date.today(),
        Enddate__c = Date.today().addDays(30),
        Amount__c = 1000,
        Quantity__c = 1,
        UnitPrice__c = 1000
      );

      Test.startTest();
      insert periodLine;
      Test.stopTest();

      InvoiceProduct__c loaded = [
        SELECT Amount__c, Quantity__c, UnitPrice__c
        FROM InvoiceProduct__c
        WHERE Id = :periodLine.Id
      ];
      System.assertEquals(
        1000,
        loaded.Amount__c,
        '仕様: Core 第11.4.2節 既にあれば上書きしない'
      );
      System.assertEquals(
        1,
        loaded.Quantity__c,
        '仕様: Core 第11.4.2節 既にあれば上書きしない'
      );
      System.assertEquals(
        1000,
        loaded.UnitPrice__c,
        '仕様: Core 第11.4.2節 既にあれば上書きしない'
      );
    }
  }

  @IsTest
  static void handlers_doNotFillWhenSourceIsUnreachable() {
    InvoiceProduct__c periodLine = new InvoiceProduct__c();
    Invoice__c invoice = new Invoice__c();
    InvoiceLine__c line = new InvoiceLine__c();
    InvoiceFieldCopyTriggerHandler.handlePeriodLineBeforeInsert(
      new List<InvoiceProduct__c>{ periodLine }
    );
    InvoiceFieldCopyTriggerHandler.handleInvoiceBeforeInsert(
      new List<Invoice__c>{ invoice }
    );
    InvoiceFieldCopyTriggerHandler.handleInvoiceLineBeforeInsert(
      new List<InvoiceLine__c>{ line }
    );
    System.assertEquals(
      null,
      periodLine.Amount__c,
      '仕様: Core 第11.4.2節 届かない相手へ空埋めしない'
    );
    System.assertEquals(
      null,
      invoice.Memo__c,
      '仕様: Core 第11.4.2節 届かない相手へ空埋めしない'
    );
    System.assertEquals(
      null,
      line.ProductCodeSnapShot__c,
      '仕様: Core 第11.4.2節 届かない相手へ空埋めしない'
    );
  }

  private static void assertInvoiceLineBlankCopyFromSoql(
    Id lineId,
    String sourceObjectApiName,
    String sourceFieldApiName,
    String expectedValue,
    String assertionMessage
  ) {
    FieldCopyDefinition__c definition = new FieldCopyDefinition__c(
      Name = 'Test_LineFrom_' + sourceObjectApiName,
      TargetObject__c = InvoiceProductFieldCopyService.TARGET_INVOICE_LINE,
      SourceObject__c = sourceObjectApiName,
      SourceFieldApiName__c = sourceFieldApiName,
      TargetFieldApiName__c = 'ProductCodeSnapShot__c'
    );
    insert definition;
    InvoiceProductFieldCopyService.resetCache();
    FieldCopyDefinitionService.resetCache();
    InvoiceLine__c queried = [
      SELECT
        ContractProduct__c,
        Product__c,
        Unit__c,
        ProductCodeSnapShot__c
      FROM InvoiceLine__c
      WHERE Id = :lineId
    ];
    InvoiceFieldCopyTriggerHandler.handleInvoiceLineBeforeInsert(
      new List<InvoiceLine__c>{ queried }
    );
    System.assertEquals(expectedValue, queried.ProductCodeSnapShot__c, assertionMessage);
    delete definition;
    InvoiceProductFieldCopyService.resetCache();
    FieldCopyDefinitionService.resetCache();
  }

  private class Fixture {
    BillingAccount__c billingAccount;
    ContractService__c service;
    ContractHistory__c history;
    Product2 product;
    ContractProduct__c contractProduct;
  }

  private static Fixture createFixture(String suffix) {
    Fixture fixture = new Fixture();
    Account account = ContractTestDataFactory.insertAccount(
      'FieldCopy ' + suffix + ' Acc'
    );
    fixture.billingAccount = new BillingAccount__c(
      Account__c = account.Id,
      BillingAddressee__c = 'トリガ宛名 御中',
      BillingEmailTo__c = 'trig@example.com',
      BillingEmailCc__c = 'trig-cc@example.com',
      BillingEmailBcc__c = 'trig-bcc@example.com',
      InvoiceDeliveryMethod__c = InvoiceDeliveryMethodService.EMAIL,
      InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER,
      InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY,
      InvoiceDateDayOfMonth__c = 1,
      InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
      PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET,
      PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END,
      PaymentTermMonthOffset__c = 0,
      PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE);
    ContractTestDataFactory.applyRequiredFields(fixture.billingAccount);
    insert fixture.billingAccount;

    fixture.service = new ContractService__c(
      Account__c = account.Id,
      BiilingAcccount__c = fixture.billingAccount.Id,
      Name = 'FieldCopy ' + suffix + ' Service',
      TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
    );
    ContractTestDataFactory.applyRequiredFields(fixture.service);
    insert fixture.service;

    fixture.history = new ContractHistory__c(
      ContractService__c = fixture.service.Id,
      Name = 'FieldCopy ' + suffix + ' History',
      historystatus__c = 'Estimate',
      Type__c = 'New',
      Version__c = 1,
      CurrentTermStartDate__c = Date.today(),
      CurrentTermEndDate__c = Date.today().addDays(30),
      EffectiveDate__c = Date.today()
    );
    ContractTestDataFactory.applyRequiredFields(fixture.history);
    ContractTestDataFactory.applyEstimateOrderedOpportunity(
      fixture.history,
      account.Id
    );
    insert fixture.history;

    fixture.product = ContractTestDataFactory.buildProduct(
      'FieldCopy ' + suffix + ' Product ' + String.valueOf(Crypto.getRandomInteger())
    );
    if (suffix == 'Journal') {
      fixture.product.ProductCode = 'FIELD-COPY-JOURNAL';
    }
    if (suffix == 'Line') {
      fixture.product.ProductCode = 'FIELD-COPY-LINE';
    }
    fixture.product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
    ContractTestDataFactory.insertProduct(fixture.product);

    fixture.contractProduct = new ContractProduct__c(
      ContractHistory__c = fixture.history.Id,
      Account__c = account.Id,
      Product__c = fixture.product.Id,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      Amount__c = 1000,
      Unit__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT,
      StartDate__c = Date.today(),
      Enddate__c = Date.today().addDays(30),
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME,
      Type__c = 'New',
      RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME
    );
    ContractTestDataFactory.applyRequiredFields(fixture.contractProduct);
    fixture.contractProduct.Amount__c = 1000;
    insert fixture.contractProduct;
    fixture.history.historystatus__c = 'Ordered';
    update fixture.history;
    return fixture;
  }
}
