@IsTest
private class RenewEstimateAutoCreateServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void insertWithCheckboxOn_doesNotCreateRenewEstimate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createSourceData(true, true);

      System.assertEquals(
        true,
        [
            SELECT RenewEstimateAutoCreateCheck__c
            FROM ContractService__c
            WHERE Id = :data.service.Id
          ]
          .RenewEstimateAutoCreateCheck__c
      );
      System.assertEquals(
        0,
        countRenewEstimates(data.service.Id),
        '作成時点から ON では Renew 見積を作らないこと'
      );
    }
  }

  @IsTest
  static void updateCheckboxOffToOn_createsRenewEstimateHistoryAndProducts() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createSourceData();

      Test.startTest();
      ContractTestDataFactory.prepareRenewEstimateAutoCreate(data.service.Id);

      List<ContractHistory__c> createdHistories = [
        SELECT
          Name,
          Type__c,
          historystatus__c,
          ContractService__c,
          Opportunity__c,
          PreviousHistory__c,
          CurrentTermStartDate__c,
          CurrentTermEndDate__c,
          EffectiveDate__c,
          Version__c,
          ApplicationDate__c
        FROM ContractHistory__c
        WHERE ContractService__c = :data.service.Id AND Type__c = 'Renew'
      ];
      System.assertEquals(1, createdHistories.size());
      ContractHistory__c createdHistory = createdHistories[0];
      List<ContractProduct__c> createdProducts = [
        SELECT
          Product__c,
          Type__c,
          BillingType__c,
          Quantity__c,
          UnitPrice__c,
          Amount__c,
          PreviousContractProduct__c,
          StartDate__c,
          Enddate__c,
          InvoiceAnchorDate__c,
          InvoiceBillingCycleCount__c
        FROM ContractProduct__c
        WHERE ContractHistory__c = :createdHistory.Id
      ];

      OrderCreateController.confirmOrder(createdHistory.Id, null, false);
      AggregateResult periodSum = [
        SELECT SUM(Amount__c) totalAmount
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :createdHistory.Id
      ];
      Test.stopTest();

      System.assertEquals(data.service.Name, createdHistory.Name);
      System.assertEquals('Renew', createdHistory.Type__c);
      System.assertEquals('Estimate', createdHistory.historystatus__c);
      System.assertEquals(data.service.Id, createdHistory.ContractService__c);
      System.assertEquals(null, createdHistory.Opportunity__c);
      System.assertEquals(
        Date.today(),
        createdHistory.ApplicationDate__c,
        '前回申込日が空なら作成日を入れること'
      );
      System.assertEquals(
        data.sourceHistory.Id,
        createdHistory.PreviousHistory__c
      );
      System.assertEquals(
        Date.newInstance(2026, 6, 1),
        createdHistory.CurrentTermStartDate__c
      );
      System.assertEquals(
        Date.newInstance(2027, 5, 31),
        createdHistory.CurrentTermEndDate__c
      );
      System.assertEquals(
        Date.newInstance(2026, 6, 1),
        createdHistory.EffectiveDate__c
      );
      System.assertEquals(2, createdHistory.Version__c);

      System.assertEquals(1, createdProducts.size());
      System.assertEquals(
        data.sourceProduct.Id,
        createdProducts[0].PreviousContractProduct__c
      );
      System.assertEquals('Renew', createdProducts[0].Type__c);
      System.assertEquals(
        ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        createdProducts[0].BillingType__c
      );
      System.assertEquals(1, createdProducts[0].Quantity__c);
      System.assertEquals(8000, createdProducts[0].UnitPrice__c);
      System.assertEquals(
        96000,
        createdProducts[0].Amount__c,
        '自動 Renew でも見積金額正本（数量×単価×月数）をセットすること'
      );
      System.assertEquals(
        Date.newInstance(2026, 6, 1),
        createdProducts[0].StartDate__c
      );
      System.assertEquals(
        Date.newInstance(2027, 5, 31),
        createdProducts[0].Enddate__c
      );
      System.assertEquals(
        Date.newInstance(2026, 6, 1),
        createdProducts[0].InvoiceAnchorDate__c,
        'Renew 継続×一括前払の請求基準日は開始日'
      );
      System.assertEquals(null, createdProducts[0].InvoiceBillingCycleCount__c);
      System.assertEquals(
        96000,
        (Decimal) periodSum.get('totalAmount'),
        '自動 Renew 未編集受注でも見積バーは Amount 合計'
      );
    }
  }

  @IsTest
  static void updateCheckboxToTrueWithoutOrderedHistory_blocksSave() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('Test Account');
      BillingAccount__c billingAccount = new BillingAccount__c(
        Account__c = account.Id,
        BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        BillingEmailTo__c = 'to@example.com',
        PaymentTerm__c = ContractTestDataFactory.TENANT_PAYMENT_TERM_MONTH_END,
        BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_25,
        AdjustInvoiceDateToBusinessDay__c = false
      );
      ContractTestDataFactory.applyRequiredFields(billingAccount);
      insert billingAccount;
      ContractService__c service = new ContractService__c(
        Name = 'No Ordered Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id,
        TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
      );
      insert service;

      Boolean thrown = false;
      String message = null;
      try {
        ContractTestDataFactory.prepareRenewEstimateAutoCreate(service.Id);
      } catch (DmlException ex) {
        thrown = true;
        message = dmlMessage(ex);
      }
      System.assertEquals(true, thrown, 'Ordered 未設定時は保存できないこと');
      System.assertEquals(
        RenewEstimateAutoCreateService.ORDERED_REQUIRED_MESSAGE,
        message
      );
    }
  }

  @IsTest
  static void updateCheckboxOffToOn_fromChange_excludesOriginalLines() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createChangeSourceWithOriginalAndRemake();
      Id remakeProductId = data.sourceProduct.Id;
      Id originalProductId = data.originalProduct.Id;

      Test.startTest();
      ContractTestDataFactory.prepareRenewEstimateAutoCreate(data.service.Id);

      ContractHistory__c renewHistory = [
        SELECT Id
        FROM ContractHistory__c
        WHERE ContractService__c = :data.service.Id AND Type__c = 'Renew'
        LIMIT 1
      ];
      List<ContractProduct__c> renewProducts = [
        SELECT
          Id,
          Quantity__c,
          UnitPrice__c,
          Amount__c,
          PreviousContractProduct__c,
          Type__c
        FROM ContractProduct__c
        WHERE ContractHistory__c = :renewHistory.Id
      ];
      Integer originalLinkedCount = [
        SELECT COUNT()
        FROM ContractProduct__c
        WHERE
          ContractHistory__c = :renewHistory.Id
          AND PreviousContractProduct__c = :originalProductId
      ];
      Test.stopTest();

      System.assertEquals(
        1,
        renewProducts.size(),
        'Original を除き Remake 1行だけ引き継ぐこと'
      );
      System.assertEquals('Renew', renewProducts[0].Type__c);
      System.assertEquals(
        remakeProductId,
        renewProducts[0].PreviousContractProduct__c,
        'Previous は Remake（現行条件）であること'
      );
      System.assertEquals(2, renewProducts[0].Quantity__c);
      System.assertEquals(10000, renewProducts[0].UnitPrice__c);
      System.assertEquals(
        240000,
        renewProducts[0].Amount__c,
        '金額は Remake 条件のみ（2×10000×12）。Original 分を足さない'
      );
      System.assertEquals(
        0,
        originalLinkedCount,
        'Original を Previous にした Renew 行が無いこと'
      );
    }
  }

  @IsTest
  static void updateCheckboxAlreadyTrue_doesNotDuplicate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createSourceData();
      ContractTestDataFactory.prepareRenewEstimateAutoCreate(data.service.Id);

      Test.startTest();
      update new ContractService__c(
        Id = data.service.Id,
        Name = 'Renew Source Service Updated'
      );
      Test.stopTest();

      System.assertEquals(1, countRenewEstimates(data.service.Id));
    }
  }

  @IsTest
  static void updateCheckboxOffToOn_spotSource_blocksSave() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createSpotSourceData();

      DmlException thrown;
      Test.startTest();
      try {
        ContractTestDataFactory.prepareRenewEstimateAutoCreate(data.service.Id);
      } catch (DmlException ex) {
        thrown = ex;
      }
      Test.stopTest();

      System.assertNotEquals(null, thrown);
      System.assert(
        dmlMessage(thrown)
          .contains(RenewEstimateAutoCreateService.SPOT_NOT_ALLOWED_MESSAGE),
        dmlMessage(thrown)
      );
      System.assertEquals(0, countRenewEstimates(data.service.Id));
    }
  }

  @IsTest
  static void updateCheckboxOffToOn_lineOneTime_blocksSave() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createSourceData();
      data.sourceProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      update data.sourceProduct;

      DmlException thrown;
      Test.startTest();
      try {
        ContractTestDataFactory.prepareRenewEstimateAutoCreate(data.service.Id);
      } catch (DmlException ex) {
        thrown = ex;
      }
      Test.stopTest();

      System.assertNotEquals(null, thrown);
      System.assert(
        dmlMessage(thrown)
          .contains(
            RenewEstimateAutoCreateService.RENEW_SOURCE_REQUIRED_MESSAGE
          ),
        dmlMessage(thrown)
      );
    }
  }

  private class TestData {
    public Account account;
    public Opportunity previousOpportunity;
    public ContractService__c service;
    public ContractHistory__c sourceHistory;
    public ContractProduct__c sourceProduct;
    public ContractProduct__c originalProduct;
  }

  private static Integer countRenewEstimates(Id serviceId) {
    return [
      SELECT COUNT()
      FROM ContractHistory__c
      WHERE ContractService__c = :serviceId AND Type__c = 'Renew'
    ];
  }

  /** Change Ordered: Original(旧) + Remake(新) が同じ期末に並ぶソース。 */
  private static TestData createChangeSourceWithOriginalAndRemake() {
    TestData data = createSourceData(false, false);
    Date termStart = data.sourceHistory.CurrentTermStartDate__c;
    Date termEnd = data.sourceHistory.CurrentTermEndDate__c;

    ContractHistory__c changeHistory = new ContractHistory__c(
      Name = 'Change Source History',
      ContractService__c = data.service.Id,
      Type__c = 'Change',
      historystatus__c = 'Estimate',
      Version__c = 2,
      CurrentTermStartDate__c = termStart,
      CurrentTermEndDate__c = termEnd,
      EffectiveDate__c = termStart,
      Opportunity__c = data.previousOpportunity.Id,
      PreviousHistory__c = data.sourceHistory.Id
    );
    insert changeHistory;

    ContractProduct__c original = new ContractProduct__c(
      ContractHistory__c = changeHistory.Id,
      Product__c = data.sourceProduct.Product__c,
      Account__c = data.account.Id,
      Quantity__c = 1,
      UnitPrice__c = 8000,
      Amount__c = -96000,
      Unit__c = 'ID/月',
      StartDate__c = termStart,
      Enddate__c = termEnd,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
      Type__c = 'Original',
      PreviousContractProduct__c = data.sourceProduct.Id
    );
    ContractProduct__c remake = new ContractProduct__c(
      ContractHistory__c = changeHistory.Id,
      Product__c = data.sourceProduct.Product__c,
      Account__c = data.account.Id,
      Quantity__c = 2,
      UnitPrice__c = 10000,
      Amount__c = 240000,
      Unit__c = 'ID/月',
      StartDate__c = termStart,
      Enddate__c = termEnd,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
      Type__c = 'Remake',
      PreviousContractProduct__c = data.sourceProduct.Id
    );
    insert new List<ContractProduct__c>{ original, remake };

    changeHistory.historystatus__c = 'Ordered';
    update changeHistory;

    data.sourceHistory = changeHistory;
    data.originalProduct = original;
    data.sourceProduct = remake;
    return data;
  }

  private static TestData createSourceData() {
    return createSourceData(true, false);
  }

  private static TestData createSourceData(
    Boolean insertAsOrdered,
    Boolean checkboxOnAtInsert
  ) {
    TestData data = new TestData();
    data.account = ContractTestDataFactory.insertAccount('Test Account');
    data.previousOpportunity = ContractTestDataFactory.insertOpportunity(
      data.account.Id,
      'Previous Opportunity'
    );

    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = data.account.Id,
      BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
      BillingEmailTo__c = 'to@example.com',
      PaymentTerm__c = ContractTestDataFactory.TENANT_PAYMENT_TERM_MONTH_END,
      BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_25,
      AdjustInvoiceDateToBusinessDay__c = false
    );
    ContractTestDataFactory.applyRequiredFields(billingAccount);
    insert billingAccount;

    data.service = new ContractService__c(
      Name = 'Renew Source Service',
      Account__c = data.account.Id,
      BiilingAcccount__c = billingAccount.Id,
      TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10),
      RenewEstimateAutoCreateCheck__c = checkboxOnAtInsert == true
    );
    insert data.service;

    Date termStart = Date.newInstance(2025, 6, 1);
    Date termEnd = Date.newInstance(2026, 5, 31);
    data.sourceHistory = new ContractHistory__c(
      Name = 'Source History',
      ContractService__c = data.service.Id,
      Type__c = 'New',
      historystatus__c = insertAsOrdered == true ? 'Ordered' : 'Estimate',
      Version__c = 1,
      CurrentTermStartDate__c = termStart,
      CurrentTermEndDate__c = termEnd,
      Opportunity__c = data.previousOpportunity.Id
    );
    insert data.sourceHistory;

    Product2 product = ContractTestDataFactory.buildProduct('Renew Product');
    product.UnitName__c = 'ID';
    product.UnitPrice__c = 8000;
    product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
    product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
    ContractTestDataFactory.insertProduct(product);

    data.sourceProduct = new ContractProduct__c(
      ContractHistory__c = data.sourceHistory.Id,
      Product__c = product.Id,
      Quantity__c = 1,
      UnitPrice__c = 8000,
      Unit__c = 'ID/月',
      StartDate__c = termStart,
      Enddate__c = termEnd,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
      Type__c = 'New'
    );
    insert data.sourceProduct;
    return data;
  }

  private static TestData createSpotSourceData() {
    TestData data = new TestData();
    data.account = ContractTestDataFactory.insertAccount('Spot Test Account');
    data.previousOpportunity = ContractTestDataFactory.insertOpportunity(
      data.account.Id,
      'Spot Previous Opportunity'
    );

    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = data.account.Id,
      BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
      BillingEmailTo__c = 'to@example.com',
      PaymentTerm__c = ContractTestDataFactory.TENANT_PAYMENT_TERM_MONTH_END,
      BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_25,
      AdjustInvoiceDateToBusinessDay__c = false
    );
    ContractTestDataFactory.applyRequiredFields(billingAccount);
    insert billingAccount;

    data.service = new ContractService__c(
      Name = 'Spot Source Service',
      Account__c = data.account.Id,
      BiilingAcccount__c = billingAccount.Id,
      TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10),
      Lifecycle__c = 'Spot'
    );
    insert data.service;

    Date termStart = Date.newInstance(2025, 6, 1);
    data.sourceHistory = new ContractHistory__c(
      Name = 'Spot Source History',
      ContractService__c = data.service.Id,
      Type__c = 'New',
      historystatus__c = 'Ordered',
      Version__c = 1,
      CurrentTermStartDate__c = termStart,
      CurrentTermEndDate__c = termStart,
      Opportunity__c = data.previousOpportunity.Id
    );
    insert data.sourceHistory;

    Product2 product = ContractTestDataFactory.buildProduct('Spot Product');
    product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
    product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
    ContractTestDataFactory.insertProduct(product, false);

    data.sourceProduct = new ContractProduct__c(
      ContractHistory__c = data.sourceHistory.Id,
      Product__c = product.Id,
      Quantity__c = 1,
      UnitPrice__c = 8000,
      Amount__c = 8000,
      StartDate__c = termStart,
      Enddate__c = termStart,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME,
      Type__c = 'New'
    );
    insert data.sourceProduct;
    return data;
  }

  private static String dmlMessage(DmlException ex) {
    if (ex == null) {
      return null;
    }
    String raw = ex.getNumDml() > 0 ? ex.getDmlMessage(0) : ex.getMessage();
    if (String.isBlank(raw)) {
      return raw;
    }
    Integer causedBy = raw.indexOf('caused by: ');
    if (causedBy >= 0) {
      raw = raw.substring(causedBy + 'caused by: '.length());
    }
    Integer newline = raw.indexOf('\n');
    if (newline >= 0) {
      raw = raw.substring(0, newline);
    }
    return raw.trim();
  }
}
