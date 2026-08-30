@IsTest
private class ContractServiceEditControllerTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void save_updatesAllowedFieldsAndCreatesNoHistory() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
      Account account = ContractTestDataFactory.insertAccount('Edit Service Acct');
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Before Name'
      );
      BillingAccount__c nextAccount = ContractTestDataFactory.insertBillingAccount(
        account.Id
      );
      Integer historiesBefore = [
        SELECT COUNT()
        FROM ContractHistory__c
        WHERE ContractService__c = :service.Id
      ];
      Integer invoicesBefore = [
        SELECT COUNT()
        FROM Invoice__c
        WHERE ContractService__c = :service.Id
      ];
      Integer productsBefore = [
        SELECT COUNT()
        FROM ContractProduct__c
        WHERE ContractHistory__r.ContractService__c = :service.Id
      ];

      Test.startTest();
      ContractServiceEditController.ContextDto context = ContractServiceEditController.getContext(
        service.Id
      );
      ContractServiceEditController.SaveResult saved = ContractServiceEditController.save(
        service.Id,
        'After Name',
        nextAccount.Id,
        8,
        'memo after',
        '{"CustomerMemo__c":"memo extra"}',
        context.lastModifiedToken,
        'service-edit-key'
      );
      Test.stopTest();

      System.assertEquals(service.Id, saved.recordId);
      ContractService__c loaded = [
        SELECT
          Name,
          BiilingAcccount__c,
          TaxPercent__c,
          CustomerMemo__c
        FROM ContractService__c
        WHERE Id = :service.Id
      ];
      System.assertEquals('After Name', loaded.Name);
      System.assertEquals(nextAccount.Id, loaded.BiilingAcccount__c);
      System.assertEquals(
        8,
        TaxCalculationUtil.fromPercentFieldStorage(loaded.TaxPercent__c),
        'Core 第3.4.1節: 税率を保存できること'
      );
      System.assertEquals('memo extra', loaded.CustomerMemo__c);
      System.assertEquals(
        historiesBefore,
        [
          SELECT COUNT()
          FROM ContractHistory__c
          WHERE ContractService__c = :service.Id
        ],
        'Core 第3.4.1節: 契約履歴を作らないこと'
      );
      System.assertEquals(
        invoicesBefore,
        [
          SELECT COUNT()
          FROM Invoice__c
          WHERE ContractService__c = :service.Id
        ],
        'Core 第3.4.1節: 請求書を作らないこと'
      );
      System.assertEquals(
        productsBefore,
        [
          SELECT COUNT()
          FROM ContractProduct__c
          WHERE ContractHistory__r.ContractService__c = :service.Id
        ],
        'Core 第3.4.1節: 見積商品を作らないこと'
      );
    }
  }

  @IsTest
  static void save_rejectsBlankNameBillingAccountAndTax() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
      Account account = ContractTestDataFactory.insertAccount('Reject Acct');
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Keep Name'
      );

      Boolean nameThrown = false;
      try {
        ContractServiceEditController.save(
          service.Id,
          '  ',
          service.BiilingAcccount__c,
          10,
          null,
          '{}'
        );
      } catch (AuraHandledException ex) {
        nameThrown = ex.getMessage().contains('名前を入力してください。');
      }
      System.assertEquals(
        true,
        nameThrown,
        'Core 第3.4.1節: 空の名前は拒否すること'
      );

      Boolean accountThrown = false;
      try {
        ContractServiceEditController.save(
          service.Id,
          'Keep Name',
          null,
          10,
          null,
          '{}'
        );
      } catch (AuraHandledException ex) {
        accountThrown = ex.getMessage().contains('請求アカウントを入力してください。');
      }
      System.assertEquals(
        true,
        accountThrown,
        'Core 第3.4.1節: 空の請求アカウントは拒否すること'
      );

      Boolean taxThrown = false;
      try {
        ContractServiceEditController.save(
          service.Id,
          'Keep Name',
          service.BiilingAcccount__c,
          null,
          null,
          '{}'
        );
      } catch (AuraHandledException ex) {
        taxThrown = ex.getMessage().contains('税率を入力してください。');
      }
      System.assertEquals(
        true,
        taxThrown,
        'Core 第3.4.1節: 空欄の税率は拒否すること'
      );
    }
  }

  @IsTest
  static void getContext_returnsCurrentValues() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
      Account account = ContractTestDataFactory.insertAccount('Context Acct');
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Context Name'
      );
      service.CustomerMemo__c = 'context memo';
      ContractServiceWriteGuard.allowPackageWrite(true);
      update service;
      ContractServiceWriteGuard.allowPackageWrite(false);

      Test.startTest();
      ContractServiceEditController.ContextDto dto = ContractServiceEditController.getContext(
        service.Id
      );
      Test.stopTest();

      System.assertEquals(service.Id, dto.recordId);
      System.assertEquals('Context Name', dto.name);
      System.assertEquals(account.Id, dto.accountId, 'Core 第3.4.1節: 取引先を返す');
      System.assertEquals(service.BiilingAcccount__c, dto.billingAccountId);
      System.assertNotEquals(
        null,
        dto.relatedBillingAccounts,
        'Core 第3.4.1節: 自取引先の請求アカウント候補を返す'
      );
      System.assertEquals(
        true,
        dto.relatedBillingAccounts.size() >= 1,
        'Core 第3.4.1節: 自取引先の請求アカウント候補を返す'
      );
      System.assertEquals(10, dto.taxPercent);
      System.assertEquals('context memo', dto.customerMemo);
      System.assertEquals('context memo', dto.customFields.get('CustomerMemo__c'));
      System.assertNotEquals(
        null,
        dto.lastModifiedToken,
        'Core 第3.4.1節: 開いたときの版を返す'
      );
    }
  }

  @IsTest
  static void save_allowsBillingAccountOfOtherAccount() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
      Account account = ContractTestDataFactory.insertAccount('Own Acct');
      Account other = ContractTestDataFactory.insertAccount('Other Acct');
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Cross BA Service'
      );
      BillingAccount__c otherBilling = ContractTestDataFactory.insertBillingAccount(
        other.Id
      );
      ContractServiceEditController.ContextDto context = ContractServiceEditController.getContext(
        service.Id
      );

      Test.startTest();
      ContractServiceEditController.SaveResult saved = ContractServiceEditController.save(
        service.Id,
        'Cross BA Service',
        otherBilling.Id,
        10,
        null,
        '{}',
        context.lastModifiedToken,
        'service-cross-ba'
      );
      Test.stopTest();

      System.assertEquals(service.Id, saved.recordId);
      ContractService__c loaded = [
        SELECT Account__c, BiilingAcccount__c
        FROM ContractService__c
        WHERE Id = :service.Id
      ];
      System.assertEquals(
        account.Id,
        loaded.Account__c,
        'Core 第3.4.1節: 契約サービスの取引先は変えない'
      );
      System.assertEquals(
        otherBilling.Id,
        loaded.BiilingAcccount__c,
        'Core 第3.4.1節: 他取引先の請求アカウントへの付け替えを許す'
      );
    }
  }

  @IsTest
  static void save_blankToken_throwsConflict() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
      Account account = ContractTestDataFactory.insertAccount('Blank Token Acct');
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Blank Token Name'
      );

      Boolean thrown = false;
      try {
        ContractServiceEditController.save(
          service.Id,
          'Blank Token Name',
          service.BiilingAcccount__c,
          10,
          null,
          '{}',
          null,
          'k1'
        );
        System.assert(
          false,
          'Core 第4.3.12節: 契約サービスを編集は比較値未指定なら拒否する'
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          ContractOptimisticLockUtil.CONFLICT_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void save_staleToken_throwsConflict() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
      Account account = ContractTestDataFactory.insertAccount('Stale Token Acct');
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Stale Token Name'
      );
      String stale = ContractOptimisticLockUtil.toToken(
        Datetime.now().addDays(-1)
      );

      Boolean thrown = false;
      try {
        ContractServiceEditController.save(
          service.Id,
          'Stale Token Name',
          service.BiilingAcccount__c,
          10,
          null,
          '{}',
          stale,
          'k-stale'
        );
        System.assert(
          false,
          'Core 第3.4.1節: 契約サービスが更新されていれば失敗し、開き直す'
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          ContractOptimisticLockUtil.CONFLICT_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void save_sameKeyRetry_returnsOneSave() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();
      Account account = ContractTestDataFactory.insertAccount('Retry Acct');
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Retry Before'
      );
      BillingAccount__c nextAccount = ContractTestDataFactory.insertBillingAccount(
        account.Id
      );
      ContractServiceEditController.ContextDto context = ContractServiceEditController.getContext(
        service.Id
      );

      Test.startTest();
      ContractServiceEditController.SaveResult first = ContractServiceEditController.save(
        service.Id,
        'Retry After',
        nextAccount.Id,
        8,
        'retry memo',
        '{}',
        context.lastModifiedToken,
        'service-retry-key'
      );
      ContractServiceEditController.SaveResult retry = ContractServiceEditController.save(
        service.Id,
        'Retry After 2',
        nextAccount.Id,
        10,
        'retry memo 2',
        '{}',
        context.lastModifiedToken,
        'service-retry-key'
      );
      Test.stopTest();

      System.assertEquals(first.recordId, retry.recordId);
      System.assertEquals(
        'service-retry-key',
        retry.businessOperationKey,
        'Core 第4.3.12節: 同じキーの再試行は1件のままにする'
      );
      ContractService__c loaded = [
        SELECT Name, TaxPercent__c
        FROM ContractService__c
        WHERE Id = :service.Id
      ];
      System.assertEquals(
        'Retry After',
        loaded.Name,
        'Core 第4.3.12節: 同じキーの再試行は先の保存のままにする'
      );
    }
  }

  @IsTest
  static void getContext_rejectsWithout08() {
    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.EDIT_SERVICE => false
    };
    Boolean thrown = false;
    try {
      ContractServiceEditController.getContext(UserInfo.getUserId());
    } catch (AuraHandledException ex) {
      thrown = true;
      System.assert(
        ex.getMessage().contains('契約サービスを編集する権限がありません'),
        '共通基盤 第10.4節: 08 なしはサーバ入口で拒否する'
      );
    } finally {
      ContractPermissionUtil.testOverrides = null;
    }
    System.assertEquals(true, thrown);
  }
}
