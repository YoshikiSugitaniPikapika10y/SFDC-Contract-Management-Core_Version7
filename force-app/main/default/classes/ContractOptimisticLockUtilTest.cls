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

      history = [
        SELECT LastModifiedDate
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      contractProduct = [
        SELECT LastModifiedDate
        FROM ContractProduct__c
        WHERE Id = :contractProduct.Id
      ];
      Datetime currentVersion = ContractOptimisticLockUtil.resolveHistoryProductDatetime(
        history.Id
      );
      Datetime expectedVersion = contractProduct.LastModifiedDate >
        history.LastModifiedDate
        ? contractProduct.LastModifiedDate
        : history.LastModifiedDate;
      System.assertEquals(
        expectedVersion,
        currentVersion,
        'Core 第4.3.12節: 版は契約履歴と配下の見積商品の最大更新日時'
      );
      String currentToken = ContractOptimisticLockUtil.toToken(currentVersion);
      ContractOptimisticLockUtil.assertRequiredHistoryProductsUnchanged(
        history.Id,
        currentToken
      );

      Boolean rejected = false;
      try {
        ContractOptimisticLockUtil.assertRequiredHistoryProductsUnchanged(
          history.Id,
          ContractOptimisticLockUtil.toToken(
            Datetime.newInstance(currentVersion.getTime() - 1)
          )
        );
      } catch (AuraHandledException ex) {
        rejected = true;
        System.assertEquals(
          ContractOptimisticLockUtil.CONFLICT_MESSAGE,
          ex.getMessage(),
          'Core 第4.3.12節: 版は契約履歴と配下の見積商品'
        );
      }
      System.assertEquals(
        true,
        rejected,
        'Core 第4.3.12節: 現行版と異なる更新情報は拒否する'
      );
      if (token != currentToken) {
        try {
          ContractOptimisticLockUtil.assertRequiredHistoryProductsUnchanged(
            history.Id,
            token
          );
          System.assert(
            false,
            'Core 第4.3.12節: 商品追加で版が進んだ場合は追加前トークンを拒否する'
          );
        } catch (AuraHandledException ex) {
          System.assertEquals(
            ContractOptimisticLockUtil.CONFLICT_MESSAGE,
            ex.getMessage()
          );
        }
      }
    }
  }

  @IsTest
  static void resolveHistoryProductDatetime_knownHistorySkipsHistoryQuery() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('Known Lm Account');
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Known Lm Service'
      );
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Known Lm History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1
      );
      ContractTestDataFactory.applyRequiredFields(history);
      ContractTestDataFactory.applyEstimateOrderedOpportunity(history, account.Id);
      insert history;
      history = [
        SELECT LastModifiedDate
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      Integer beforeKnown = Limits.getQueries();
      Datetime withKnown = ContractOptimisticLockUtil.resolveHistoryProductDatetime(
        history.Id,
        history.LastModifiedDate
      );
      Integer usedKnown = Limits.getQueries() - beforeKnown;
      Integer beforeFull = Limits.getQueries();
      Datetime withoutKnown = ContractOptimisticLockUtil.resolveHistoryProductDatetime(
        history.Id
      );
      Integer usedFull = Limits.getQueries() - beforeFull;
      System.assertEquals(
        withoutKnown,
        withKnown,
        'Core 第5.2節: ロック済み契約履歴の更新日時でも版は同じ'
      );
      System.assert(
        usedKnown < usedFull,
        'Core 第5.2節: 同一処理でロック済み契約履歴を取り直さない'
      );

      ContractOptimisticLockUtil.productMaxSelectCount = 0;
      List<ContractProduct__c> products = [
        SELECT LastModifiedDate
        FROM ContractProduct__c
        WHERE ContractHistory__c = :history.Id
      ];
      Integer beforeProducts = Limits.getQueries();
      Datetime withProducts = ContractOptimisticLockUtil.resolveHistoryProductDatetime(
        history.Id,
        history.LastModifiedDate,
        products
      );
      Integer usedProducts = Limits.getQueries() - beforeProducts;
      System.assertEquals(withKnown, withProducts);
      System.assertEquals(
        0,
        usedProducts,
        'Core 第4.3.12節: 読んだ見積商品の MAX を取り直さない'
      );
      System.assertEquals(0, ContractOptimisticLockUtil.productMaxSelectCount);
    }
  }
}
