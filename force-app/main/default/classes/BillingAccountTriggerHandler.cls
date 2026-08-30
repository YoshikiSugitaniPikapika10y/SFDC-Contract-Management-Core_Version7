/**
 * 請求アカウントのキー確定と参照あり更新。確認ゲートは持たない。
 */
public without sharing class BillingAccountTriggerHandler {
  /** 仕様: Core 第3.3.1節、第7.2節、第7.5節、第3.3.7節 */
  public static void handleBeforeInsert(List<BillingAccount__c> newRecords) {
    BillingAccountKeyService.assignOnInsert(newRecords);
    assertSchedule(newRecords);
    InvoiceDeliveryMethodService.assertRequiredOnBillingAccount(newRecords);
  }

  /** 仕様: Core 第3.3.1節、第7.2節、第7.5節、第3.3.7節 */
  public static void handleBeforeUpdate(
    List<BillingAccount__c> newRecords,
    Map<Id, BillingAccount__c> oldMap
  ) {
    BillingAccountKeyService.rejectKeyChange(newRecords, oldMap);
    assertSchedule(newRecords);
    InvoiceDeliveryMethodService.assertRequiredOnBillingAccount(newRecords);
  }

  /** 仕様: Core 第3.3.1節 */
  public static void handleAfterInsert(List<BillingAccount__c> newRecords) {
    BillingAccountKeyService.fillBlankKeys(newRecords);
    ContractOperationLogService.writeMasters('SaveBillingAccount', newRecords);
  }

  public static void handleAfterUpdate(
    List<BillingAccount__c> newRecords,
    Map<Id, BillingAccount__c> oldMap
  ) {
    ContractOperationLogService.writeMasters('SaveBillingAccount', newRecords);
  }

  public static void handleAfterDelete(List<BillingAccount__c> oldRecords) {
    ContractOperationLogService.writeMasters('DeleteBillingAccount', oldRecords);
  }

  static void assertSchedule(List<BillingAccount__c> records) {
    if (records == null) {
      return;
    }
    for (BillingAccount__c record : records) {
      try {
        BillingScheduleService.assertSchedule(record);
      } catch (BillingScheduleService.ScheduleException ex) {
        record.addError(ex.getMessage());
      }
    }
  }
}
