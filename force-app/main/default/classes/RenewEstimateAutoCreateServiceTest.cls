@IsTest
private class RenewEstimateAutoCreateServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void insertWithCheckboxOn_doesNotCreateRenewEstimate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createSourceData();

      Test.startTest();
      // 作成時点からチェック ON でも自動作成は発火しない（OFF→ON の更新のみ）。
      Opportunity renewOpportunity = ContractTestDataFactory.insertOpportunity(
        data.account.Id,
        'Renew Opportunity Insert On',
        data.previousOpportunity.Id,
        true,
        data.service.Id
      );
      Test.stopTest();

      System.assertEquals(
        true,
        renewOpportunity.RenewEstimateAutoCreateCheck__c,
        '作成時チェック ON の状態であること'
      );
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM ContractHistory__c
          WHERE Opportunity__c = :renewOpportunity.Id AND Type__c = 'Renew'
        ],
        '商談新規作成時（最初から ON）では Renew 見積を作らないこと'
      );
    }
  }

  @IsTest
  static void updateCheckboxOffToOn_createsRenewEstimateHistoryAndProducts() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createSourceData();

      // いったん OFF で作成し、OFF→ON 更新で発火させる。
      Opportunity renewOpportunity = ContractTestDataFactory.insertOpportunity(
        data.account.Id,
        'Renew Opportunity',
        data.previousOpportunity.Id,
        false,
        data.service.Id
      );

      Test.startTest();
      ContractTestDataFactory.prepareRenewEstimateAutoCreate(
        renewOpportunity,
        data.service.Id
      );
      update renewOpportunity;

      // フィクスチャ＋同期の SOQL を使い切らないよう、検証クエリも startTest 内で実行する
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
          Version__c
        FROM ContractHistory__c
        WHERE Opportunity__c = :renewOpportunity.Id
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

      // 未編集のまま受注しても見積バーが 0 にならないこと
      // （重い受注も同一 startTest 枠内で実行し、stopTest 後の残枠不足を避ける）
      OrderCreateController.confirmOrder(createdHistory.Id, null, false);
      AggregateResult periodSum = [
        SELECT SUM(Amount__c) totalAmount
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :createdHistory.Id
      ];
      Test.stopTest();

      System.assertEquals('Renew Opportunity', createdHistory.Name);
      System.assertEquals('Renew', createdHistory.Type__c);
      System.assertEquals('Estimate', createdHistory.historystatus__c);
      System.assertEquals(data.service.Id, createdHistory.ContractService__c);
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
      System.assertEquals(ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING, createdProducts[0].BillingType__c);
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
      System.assertEquals(
        null,
        createdProducts[0].InvoiceBillingCycleCount__c
      );
      System.assertEquals(
        96000,
        (Decimal) periodSum.get('totalAmount'),
        '自動 Renew 未編集受注でも見積バーは Amount 合計'
      );
    }
  }

  @IsTest
  static void updateCheckboxToTrueWithoutPreviousOpportunity_blocksSave() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('Test Account');
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Renew Opportunity',
        null,
        false
      );

      Boolean thrown = false;
      String message = null;
      try {
        opportunity.RenewEstimateAutoCreateCheck__c = true;
        update opportunity;
      } catch (DmlException ex) {
        thrown = true;
        message = dmlMessage(ex);
      }
      System.assertEquals(true, thrown, '前商談未設定時は保存できないこと');
      System.assertEquals(
        RenewEstimateAutoCreateService.PREVIOUS_OPPORTUNITY_REQUIRED_MESSAGE,
        message
      );
    }
  }

  @IsTest
  static void updateCheckboxToTrueWithoutOrderedHistory_blocksSaveWithOrderedMessage() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('Test Account');
      Opportunity previousOpportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Previous Opportunity'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Renew Opportunity',
        previousOpportunity.Id,
        false
      );

      Boolean thrown = false;
      String message = null;
      try {
        opportunity.RenewEstimateAutoCreateCheck__c = true;
        update opportunity;
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
  static void updateCheckboxToTrue_createsRenewEstimate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createSourceData();
      Opportunity renewOpportunity = ContractTestDataFactory.insertOpportunity(
        data.account.Id,
        'Renew Opportunity',
        data.previousOpportunity.Id,
        false,
        data.service.Id
      );

      Test.startTest();
      ContractTestDataFactory.prepareRenewEstimateAutoCreate(
        renewOpportunity,
        data.service.Id
      );
      update renewOpportunity;
      Test.stopTest();

      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM ContractHistory__c
          WHERE Opportunity__c = :renewOpportunity.Id AND Type__c = 'Renew'
        ]
      );
    }
  }

  @IsTest
  static void updateCheckboxOffToOn_fromChange_excludesOriginalLines() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      // Change Ordered: Original(旧条件) + Remake(新条件) が同じ期末。
      // 自動 Renew は手動と同じく Remake だけ引き継ぎ、Original で金額が倍にならないこと。
      TestData data = createChangeSourceWithOriginalAndRemake();
      Id remakeProductId = data.sourceProduct.Id;
      Id originalProductId = data.originalProduct.Id;

      // Change Ordered の請求生成で外側 SOQL を使い切るため、商談 insert 以降を startTest に入れる
      Test.startTest();
      Opportunity renewOpportunity = ContractTestDataFactory.insertOpportunity(
        data.account.Id,
        'Renew From Change',
        data.previousOpportunity.Id,
        false,
        data.service.Id
      );
      ContractTestDataFactory.prepareRenewEstimateAutoCreate(
        renewOpportunity,
        data.service.Id
      );
      update renewOpportunity;

      // Change Ordered フィクスチャが外側 SOQL を使い切るため、検証クエリも startTest 内で実行する
      ContractHistory__c renewHistory = [
        SELECT Id
        FROM ContractHistory__c
        WHERE Opportunity__c = :renewOpportunity.Id AND Type__c = 'Renew'
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
      Opportunity renewOpportunity = ContractTestDataFactory.insertOpportunity(
        data.account.Id,
        'Renew Opportunity',
        data.previousOpportunity.Id,
        false,
        data.service.Id
      );
      ContractTestDataFactory.prepareRenewEstimateAutoCreate(
        renewOpportunity,
        data.service.Id
      );
      update renewOpportunity;

      Test.startTest();
      renewOpportunity.Name = 'Renew Opportunity Updated';
      update renewOpportunity;
      Test.stopTest();

      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM ContractHistory__c
          WHERE Opportunity__c = :renewOpportunity.Id AND Type__c = 'Renew'
        ]
      );
    }
  }

  @IsTest
  static void updateCheckboxOffToOn_spotSource_blocksSave() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createSpotSourceData();
      Opportunity renewOpportunity = ContractTestDataFactory.insertOpportunity(
        data.account.Id,
        'Spot Renew Opportunity',
        data.previousOpportunity.Id,
        false,
        data.service.Id
      );

      DmlException thrown;
      Test.startTest();
      try {
        ContractTestDataFactory.prepareRenewEstimateAutoCreate(
          renewOpportunity,
          data.service.Id
        );
        update renewOpportunity;
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
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM ContractHistory__c
          WHERE Opportunity__c = :renewOpportunity.Id AND Type__c = 'Renew'
        ]
      );
    }
  }

  @IsTest
  static void updateCheckboxOffToOn_lineOneTime_blocksSave() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createSourceData();
      data.sourceProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      update data.sourceProduct;

      Opportunity renewOpportunity = ContractTestDataFactory.insertOpportunity(
        data.account.Id,
        'Line One Time Renew Opportunity',
        data.previousOpportunity.Id,
        false,
        data.service.Id
      );

      DmlException thrown;
      Test.startTest();
      try {
        ContractTestDataFactory.prepareRenewEstimateAutoCreate(
          renewOpportunity,
          data.service.Id
        );
        update renewOpportunity;
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

  /** Change Ordered: Original(旧) + Remake(新) が同じ期末に並ぶソース。 */
  private static TestData createChangeSourceWithOriginalAndRemake() {
    // New を Estimate のままにし、二重の請求生成で SOQL 101 に達しないようにする。
    TestData data = createSourceData(false);
    // Change は商品投入後に Ordered へ（AfterInsert 時点では Original 検証が通らない）。
    Date termStart = data.sourceHistory.CurrentTermStartDate__c;
    Date termEnd = data.sourceHistory.CurrentTermEndDate__c;
    // Remake が期首から数量・単価変更するため、有効日は課金イベント最早日＝期首。

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
    return createSourceData(true);
  }

  private static TestData createSourceData(Boolean insertAsOrdered) {
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
      TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
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
