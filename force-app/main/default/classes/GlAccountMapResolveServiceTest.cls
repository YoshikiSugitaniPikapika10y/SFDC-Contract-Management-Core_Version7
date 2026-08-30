@IsTest
private class GlAccountMapResolveServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void resolve_rejectsWhenNoMatch() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Boolean thrown = false;
      try {
        GlAccountMapResolveService.resolve(
          'AccountsReceivable',
          'InvoiceLine',
          new ConditionEvaluationService.Context()
        );
      } catch (Exception ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('勘定科目割当がありません'),
          'Accounting 第6.3節: 一致0件は科目未設定として拒否する'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void resolve_rejectsTiedHighestPriority() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccount__c first = insertAccount('Map First');
      GlAccount__c second = insertAccount('Map Second');
      insertMap(first.Id, 10, 'Tie A');
      insertMap(second.Id, 10, 'Tie B');
      Boolean thrown = false;
      try {
        GlAccountMapResolveService.resolve(
          'AccountsReceivable',
          'InvoiceLine',
          new ConditionEvaluationService.Context()
        );
      } catch (Exception ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('最高優先度の勘定科目割当が複数'),
          'Accounting 第6.3節: 同一最高優先度の複数一致は推測しない'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void resolve_usesHighestPriorityOnly() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccount__c high = insertAccount('Map High');
      GlAccount__c low = insertAccount('Map Low');
      GlAccountMap__c chosen = insertMap(high.Id, 20, 'High');
      insertMap(low.Id, 10, 'Low');
      GlAccountMapResolveService.ResolvedAccount resolved = GlAccountMapResolveService.resolve(
        'AccountsReceivable',
        'InvoiceLine',
        new ConditionEvaluationService.Context()
      );
      System.assertEquals(
        chosen.Id,
        resolved.assignmentId,
        'Accounting 第6.3節: 最高優先度が1件ならそれを採用し低優先度は無視する'
      );
      System.assertEquals(high.Id, resolved.accountId);
    }
  }

  @IsTest
  static void resolve_errorsWhenWinningAccountIsInactive() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccount__c inactive = insertAccount('Map Inactive');
      GlAccount__c fallback = insertAccount('Map Fallback');
      insertMap(inactive.Id, 20, 'Inactive High');
      insertMap(fallback.Id, 10, 'Active Low');
      inactive.IsActive__c = false;
      update inactive;

      Boolean thrown = false;
      try {
        GlAccountMapResolveService.resolve(
          'AccountsReceivable',
          'InvoiceLine',
          new ConditionEvaluationService.Context()
        );
      } catch (Exception ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('科目が無効'),
          'Accounting 第4.1節・第6.2節: 初回生成は無効科目を飛ばさずエラーにする。実際: ' +
            ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void save_keepsMappingWhenAccountLaterDeactivated() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccount__c account = insertAccount('Map Keep');
      GlAccountMap__c mapping = insertMap(account.Id, 10, 'Keep');
      account.IsActive__c = false;
      update account;
      update new GlAccountMap__c(Id = mapping.Id, Name = 'Keep Renamed');
      GlAccountMap__c stored = [
        SELECT Id, Name, Account__c
        FROM GlAccountMap__c
        WHERE Id = :mapping.Id
      ];
      System.assertEquals(
        'Keep Renamed',
        stored.Name,
        'Accounting 第4.1節: 無効化しても既存割当は残す。名称変更はできる'
      );
      System.assertEquals(account.Id, stored.Account__c);
    }
  }

  @IsTest
  static void save_rejectsReplacingAccountWithInactive() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccount__c active = insertAccount('Map Active Keep');
      GlAccount__c inactive = insertAccount('Map Inactive New');
      GlAccountMap__c mapping = insertMap(active.Id, 10, 'Replace');
      inactive.IsActive__c = false;
      update inactive;
      Boolean thrown = false;
      try {
        update new GlAccountMap__c(Id = mapping.Id, Account__c = inactive.Id);
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('無効な勘定科目を新しく割り当てることはできません。'),
          'Accounting 第4.1節: 既存割当の科目を無効科目へ付け替えない。実際: ' +
            ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void save_rejectsSlotCategoryChangeOnExistingMap() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccount__c asset = insertAccount('Map Asset Slot');
      GlAccountMap__c mapping = insertMap(asset.Id, 10, 'Slot Change');
      Boolean thrown = false;
      try {
        update new GlAccountMap__c(
          Id = mapping.Id,
          SlotKey__c = 'Revenue'
        );
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('スロットと科目の勘定区分が一致していません。'),
          'Accounting 第6.2節: 既存割当でもスロット変更時は勘定区分を一致させる。実際: ' +
            ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void save_rejectsInactiveAccountAndCategoryMismatch() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccount__c inactive = insertAccount('Map Save Inactive');
      inactive.IsActive__c = false;
      update inactive;
      GlAccount__c expense = new GlAccount__c(
        Name = 'Map Expense',
        AccountType__c = 'Expense',
        IsActive__c = true
      );
      insert expense;

      Boolean inactiveThrown = false;
      try {
        insertMap(inactive.Id, 10, 'New Inactive');
      } catch (DmlException ex) {
        inactiveThrown = true;
        System.assert(
          ex.getMessage().contains('無効な勘定科目を新しく割り当てることはできません。'),
          'Accounting 第4.1節: 新規割当に無効科目を指定できない。実際: ' +
            ex.getMessage()
        );
      }
      System.assertEquals(true, inactiveThrown);

      Boolean categoryThrown = false;
      try {
        insertMap(expense.Id, 10, 'Wrong Category');
      } catch (DmlException ex) {
        categoryThrown = true;
        System.assert(
          ex.getMessage().contains('スロットと科目の勘定区分が一致していません。'),
          'Accounting 第6.2節: スロットと実勘定の勘定区分を一致させる。実際: ' +
            ex.getMessage()
        );
      }
      System.assertEquals(true, categoryThrown);
    }
  }

  @IsTest
  static void save_matchesLiabilitySlotToLiabilityAccount() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccount__c liability = insertAccount('Map Liability', 'Liability');
      GlAccountMap__c mapping = insertMap(
        liability.Id,
        10,
        'DEF Map',
        'DeferredRevenue'
      );
      System.assertNotEquals(
        null,
        mapping.Id,
        'Accounting 第6.2節: 前受収益スロットは負債科目と一致する'
      );
      GlAccount__c asset = insertAccount('Map Asset On DEF');
      Boolean thrown = false;
      try {
        insertMap(asset.Id, 11, 'DEF Wrong', 'DeferredRevenue');
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('スロットと科目の勘定区分が一致していません。'),
          'Accounting 第6.2節: 負債スロットへ資産科目は割り当てられない。実際: ' +
            ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  private static GlAccount__c insertAccount(String name) {
    return insertAccount(name, 'Asset');
  }

  private static GlAccount__c insertAccount(String name, String accountType) {
    GlAccount__c account = new GlAccount__c(
      Name = name,
      AccountType__c = accountType,
      IsActive__c = true
    );
    insert account;
    return account;
  }

  private static GlAccountMap__c insertMap(Id accountId, Integer priority, String name) {
    return insertMap(accountId, priority, name, 'AccountsReceivable');
  }

  private static GlAccountMap__c insertMap(
    Id accountId,
    Integer priority,
    String name,
    String slotKey
  ) {
    GlAccountMap__c mapping = new GlAccountMap__c(
      Name = name,
      Account__c = accountId,
      SlotKey__c = slotKey,
      EvaluationContext__c = 'InvoiceLine',
      ConditionSourceType__c = 'None',
      Priority__c = priority,
      IsActive__c = true
    );
    insert mapping;
    return mapping;
  }
}
