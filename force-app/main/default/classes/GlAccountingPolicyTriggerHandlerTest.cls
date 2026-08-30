@IsTest
private class GlAccountingPolicyTriggerHandlerTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void beforeInsert_rejectsSecondRecord() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Boolean thrown = false;
      try {
        GlAccountingPolicy__c second = GlAccountingPolicyService.newOrgDefault();
        second.Name = 'Second';
        insert second;
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('組織内1件だけ'),
          'Accounting 第3.1節: 2件目の作成を拒否する'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void beforeUpdate_rejectsChangeWhenFrozen() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      GlAccountingPolicyService.freezeOnFirstConfirm();
      GlAccountingPolicy__c policy = GlAccountingPolicyService.requireOrgPolicy();
      Boolean thrown = false;
      try {
        policy.AccountingEnabled__c = true;
        update policy;
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('固定済みの会計方針は変更できません'),
          'Accounting 第3.1節: 固定後は全経路で変更を拒否する'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void beforeDelete_rejectsFrozenWith103() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      GlAccountingPolicyService.freezeOnFirstConfirm();
      GlAccountingPolicy__c policy = GlAccountingPolicyService.requireOrgPolicy();
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.DELETE_RECORDS => true
      };
      Boolean thrown = false;
      try {
        delete policy;
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('固定済みの会計方針は削除できません'),
          'Accounting 第3.1節: 固定後の削除は 103 では回避しない'
        );
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void beforeDelete_allowsFrozenWith104() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      GlAccountingPolicyService.freezeOnFirstConfirm();
      GlAccountingPolicy__c policy = GlAccountingPolicyService.requireOrgPolicy();
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.MIGRATE_ALL => true
      };
      try {
        delete policy;
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
      System.assertEquals(
        0,
        [SELECT COUNT() FROM GlAccountingPolicy__c WHERE Id = :policy.Id],
        'Accounting 第3.1節・共通基盤 第3.6節: 固定後の削除は 104 だけ通す'
      );
    }
  }
}
