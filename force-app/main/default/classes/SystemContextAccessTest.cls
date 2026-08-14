@IsTest
private class SystemContextAccessTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void insertAndUpdateInSystemMode() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'System Context Account'
      );

      ContractService__c service = new ContractService__c(
        Name = 'System Context Service',
        Account__c = account.Id
      );
      SystemContextAccess.insertRecords(new List<SObject>{ service });

      service.Name = 'System Context Service Updated';
      SystemContextAccess.updateRecords(new List<SObject>{ service });

      ContractService__c saved = [
        SELECT Name
        FROM ContractService__c
        WHERE Id = :service.Id
        WITH SYSTEM_MODE
      ];
      System.assertEquals('System Context Service Updated', saved.Name);
    }
  }

  @IsTest
  static void handlesEmptyListsWithoutError() {
    SystemContextAccess.insertRecords(new List<SObject>());
    SystemContextAccess.insertRecords(null);
    SystemContextAccess.updateRecords(new List<SObject>());
    SystemContextAccess.updateRecords(null);
    SystemContextAccess.deleteRecords(new List<SObject>());
    SystemContextAccess.deleteRecords(null);
    SystemContextAccess.upsertRecords(new List<SObject>());
    SystemContextAccess.upsertRecords(null);
    System.assertEquals(
      0,
      SystemContextAccess.insertRecords(new List<SObject>(), false).size()
    );
  }

  @IsTest
  static void deleteAndUpsertInSystemMode() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Delete Upsert Account'
      );

      ContractService__c service = new ContractService__c(
        Name = 'Delete Upsert Service',
        Account__c = account.Id
      );
      SystemContextAccess.insertRecords(new List<SObject>{ service }, false);

      service.Name = 'Delete Upsert Service Updated';
      SystemContextAccess.upsertRecords(new List<SObject>{ service }, true);

      SystemContextAccess.deleteRecords(new List<SObject>{ service }, true);

      List<ContractService__c> remaining = [
        SELECT Id
        FROM ContractService__c
        WHERE Id = :service.Id
        WITH SYSTEM_MODE
      ];
      System.assertEquals(0, remaining.size());
    }
  }
}
