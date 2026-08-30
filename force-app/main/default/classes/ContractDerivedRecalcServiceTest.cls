@IsTest
private class ContractDerivedRecalcServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void recalculate_blocksWithout102() {
    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.FIX_CONTRACT => false,
      ContractPermissionUtil.MIGRATE_ALL => false
    };
    Boolean blocked = false;
    try {
      ContractDerivedRecalcService.recalculate(new Set<Id>());
    } catch (AuraHandledException ex) {
      blocked = true;
      System.assertEquals(
        '契約と見積の再計算を実行する権限がありません。',
        ex.getMessage()
      );
    } finally {
      ContractPermissionUtil.testOverrides = null;
    }
    System.assertEquals(true, blocked);
  }

  @IsTest
  static void recalculate_runsWith102() {
    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.FIX_CONTRACT => true
    };
    Test.startTest();
    ContractDerivedRecalcService.recalculate(new Set<Id>());
    Test.stopTest();
    ContractPermissionUtil.testOverrides = null;
  }
}
