@IsTest
private class ContractOptimisticLockUtilTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void toToken_and_assert_roundTrip() {
    Datetime stamp = Datetime.newInstance(2026, 8, 10, 1, 2, 3);
    String token = ContractOptimisticLockUtil.toToken(stamp);
    System.assertEquals(String.valueOf(stamp.getTime()), token);
    ContractOptimisticLockUtil.assertUnchanged(stamp, token, 'テスト');
  }

  @IsTest
  static void toToken_null_returnsNull() {
    System.assertEquals(null, ContractOptimisticLockUtil.toToken(null));
    System.assertEquals(null, ContractOptimisticLockUtil.parseToken(null));
    System.assertEquals(null, ContractOptimisticLockUtil.parseToken(''));
  }

  @IsTest
  static void assertUnchanged_blankToken_skips() {
    ContractOptimisticLockUtil.assertUnchanged(Datetime.now(), null, 'テスト');
    ContractOptimisticLockUtil.assertUnchanged(Datetime.now(), '', 'テスト');
  }

  @IsTest
  static void assertUnchanged_nullActual_skipsCompare() {
    ContractOptimisticLockUtil.assertUnchanged(
      null,
      ContractOptimisticLockUtil.toToken(Datetime.now()),
      'テスト'
    );
  }

  @IsTest
  static void assertHistoryUnchanged_nullHistory_throws() {
    try {
      ContractOptimisticLockUtil.assertHistoryUnchanged(null, '1');
      System.assert(false, 'Expected missing history');
    } catch (AuraHandledException ex) {
      System.assertEquals('契約履歴が見つかりません。', ex.getMessage());
    }
  }

  @IsTest
  static void assertUnchanged_mismatch_throws() {
    Datetime actual = Datetime.newInstance(2026, 8, 10, 1, 2, 3);
    String stale = ContractOptimisticLockUtil.toToken(actual.addSeconds(-10));
    try {
      ContractOptimisticLockUtil.assertUnchanged(actual, stale, '契約履歴');
      System.assert(false, 'Expected conflict');
    } catch (AuraHandledException ex) {
      System.assertEquals(
        ContractOptimisticLockUtil.CONFLICT_MESSAGE,
        ex.getMessage()
      );
    }
  }

  @IsTest
  static void assertUnchanged_invalidToken_throws() {
    try {
      ContractOptimisticLockUtil.assertUnchanged(
        Datetime.now(),
        'not-a-number',
        '契約履歴'
      );
      System.assert(false, 'Expected conflict');
    } catch (AuraHandledException ex) {
      System.assertEquals(
        ContractOptimisticLockUtil.CONFLICT_MESSAGE,
        ex.getMessage()
      );
    }
  }

  @IsTest
  static void assertRequiredUnchanged_blankOrMissingActual_throws() {
    for (Integer scenario = 0; scenario < 2; scenario++) {
      try {
        ContractOptimisticLockUtil.assertRequiredUnchanged(
          scenario == 0 ? Datetime.now() : null,
          scenario == 0
            ? null
            : ContractOptimisticLockUtil.toToken(Datetime.now()),
          'テスト'
        );
        System.assert(false, 'Expected required optimistic lock conflict');
      } catch (AuraHandledException ex) {
        System.assertEquals(
          ContractOptimisticLockUtil.CONFLICT_MESSAGE,
          ex.getMessage()
        );
      }
    }
  }

  @IsTest
  static void parseToken_trimsWhitespace() {
    Datetime stamp = Datetime.newInstance(2026, 8, 10, 1, 2, 3);
    String token = ContractOptimisticLockUtil.toToken(stamp);
    System.assertEquals(
      stamp.getTime(),
      ContractOptimisticLockUtil.parseToken('  ' + token + '  ').getTime()
    );
  }

  @IsTest
  static void assertRequiredHistoryUnchanged_nullHistory_throws() {
    try {
      ContractOptimisticLockUtil.assertRequiredHistoryUnchanged(null, '1');
      System.assert(false, 'Expected missing history');
    } catch (AuraHandledException ex) {
      System.assertEquals('契約履歴が見つかりません。', ex.getMessage());
    }
  }

  @IsTest
  static void resolveHistoryProductDatetime_nullId_returnsNull() {
    System.assertEquals(
      null,
      ContractOptimisticLockUtil.resolveHistoryProductDatetime(null)
    );
    System.assertEquals(
      null,
      ContractOptimisticLockUtil.toHistoryProductToken(null)
    );
  }

  @IsTest
  static void assertRequiredHistoryProductsUnchanged_comparesHistoryAndProducts() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('Lock Account');
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Lock Service'
      );
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Lock History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1
      );
      ContractTestDataFactory.applyRequiredFields(history);
      ContractTestDataFactory.applyEstimateOrderedOpportunity(history, account.Id);
      insert history;

      String token = ContractOptimisticLockUtil.toHistoryProductToken(
        history.Id
      );
      ContractOptimisticLockUtil.assertRequiredHistoryProductsUnchanged(
        history.Id,
        token
      );
      ContractOptimisticLockUtil.assertRequiredHistoryUnchanged(
        [
          SELECT LastModifiedDate
          FROM ContractHistory__c
          WHERE Id = :history.Id
        ],
        ContractOptimisticLockUtil.toToken(
          [
            SELECT LastModifiedDate
            FROM ContractHistory__c
            WHERE Id = :history.Id
          ]
          .LastModifiedDate
        )
      );

      Product2 product = ContractTestDataFactory.buildProduct('Lock Product');
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      ContractTestDataFactory.insertProduct(product);
      ContractProduct__c contractProduct = new ContractProduct__c(
        ContractHistory__c = history.Id,
        Account__c = account.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        Amount__c = 1000,
        StartDate__c = Date.today(),
        Enddate__c = Date.today(),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME,
        Type__c = 'New',
        RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME
      );
      ContractTestDataFactory.applyRequiredFields(contractProduct);
      contractProduct.Amount__c = 1000;
      insert contractProduct;

      Boolean rejected = false;
      try {
        ContractOptimisticLockUtil.assertRequiredHistoryProductsUnchanged(
          history.Id,
          token
        );
      } catch (AuraHandledException ex) {
        rejected = true;
        System.assertEquals(
          ContractOptimisticLockUtil.CONFLICT_MESSAGE,
          ex.getMessage(),
          'Core 第4.3.12節: 版は契約履歴と配下の見積商品'
        );
      }
      System.assertEquals(true, rejected);
    }
  }
}
