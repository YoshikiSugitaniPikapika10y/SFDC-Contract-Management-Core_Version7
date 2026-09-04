/**
 * 仕様: 共通基盤 第3.2節・第3.8節・第10.4節。操作の可否は Loop_* カスタム権限。
 * 01・02・19・21・22 にカスタム権限は無い。101〜103 はテスト既定 OFF。
 */
public without sharing class ContractPermissionUtil {
  public static final String ESTIMATE = 'Loop_03_Can_Estimate';
  public static final String ISSUE_ESTIMATE = 'Loop_04_Can_IssueEstimate';
  public static final String SEND_ESTIMATE = 'Loop_05_Can_SendEstimate';
  public static final String ORDER = 'Loop_06_Can_Order';
  public static final String REVERT = 'Loop_07_Can_Revert';
  public static final String EDIT_SERVICE = 'Loop_08_Can_EditService';
  public static final String VIEW_INVOICE = 'Loop_09_Can_ViewInvoice';
  public static final String EDIT_DRAFT_INVOICE = 'Loop_10_Can_EditDraftInvoice';
  public static final String CONFIRM_INVOICE = 'Loop_11_Can_ConfirmInvoice';
  public static final String SEND_INVOICE = 'Loop_12_Can_SendInvoice';
  public static final String INVOICE_PAYMENT = 'Loop_13_Can_InvoicePayment';
  public static final String MANUAL_JOURNAL = 'Loop_14_Can_ManualJournal';
  public static final String CANCEL_INVOICE = 'Loop_15_Can_CancelInvoice';
  public static final String LOCK_JOURNAL = 'Loop_16_Can_LockJournal';
  public static final String UNLOCK_JOURNAL = 'Loop_17_Can_UnlockJournal';
  public static final String CROSS_WORK = 'Loop_18_Can_CrossWork';
  public static final String ORG_SETTINGS = 'Loop_20_Can_OrgSettings';
  public static final String FIX_CONTRACT = 'Loop_102_Can_FixContract';
  public static final String DELETE_RECORDS = 'Loop_103_Can_DeleteRecords';
  public static final String MIGRATE_ALL = 'Loop_101_Can_MigrateAll';

  private static final Set<String> INVOICE_BOARD_PERMISSIONS = new Set<String>{
    VIEW_INVOICE,
    EDIT_DRAFT_INVOICE,
    CONFIRM_INVOICE,
    SEND_INVOICE,
    INVOICE_PAYMENT,
    MANUAL_JOURNAL,
    CANCEL_INVOICE,
    LOCK_JOURNAL,
    UNLOCK_JOURNAL
  };

  private static final Set<String> IRREGULAR_PERMISSIONS = new Set<String>{
    FIX_CONTRACT,
    DELETE_RECORDS,
    MIGRATE_ALL
  };

  /** テスト既定: 03〜21 は許可。101〜103 は拒否。false にすると未オーバーライド分も拒否。 */
  @TestVisible
  private static Boolean testAllowAll = true;

  /** テスト用。キーはカスタム権限 API 名。 */
  @TestVisible
  private static Map<String, Boolean> testOverrides;

  public static Boolean has(String permissionName) {
    if (String.isBlank(permissionName)) {
      return false;
    }
    if (Test.isRunningTest()) {
      if (testOverrides != null && testOverrides.containsKey(permissionName)) {
        return testOverrides.get(permissionName) == true;
      }
      if (IRREGULAR_PERMISSIONS.contains(permissionName)) {
        return false;
      }
      return testAllowAll != false;
    }
    return FeatureManagement.checkPermission(permissionName);
  }

  /** 仕様: 共通基盤 第3.6節。101 は 102・103 を含む。 */
  public static Boolean hasFixContract() {
    return has(FIX_CONTRACT) || has(MIGRATE_ALL);
  }

  public static Boolean hasDeleteRecords() {
    return has(DELETE_RECORDS) || has(MIGRATE_ALL);
  }

  public static Boolean hasMigrateAll() {
    return has(MIGRATE_ALL);
  }

  /** 仕様: 共通基盤 第3.1節。請求ボード閲覧は 09、または作業系 10〜17。 */
  public static Boolean canViewInvoiceBoard() {
    for (String permissionName : INVOICE_BOARD_PERMISSIONS) {
      if (has(permissionName)) {
        return true;
      }
    }
    return false;
  }

  public static void assertHas(String permissionName, String message) {
    if (has(permissionName)) {
      return;
    }
    String resolved = String.isNotBlank(message)
      ? message
      : 'この操作を実行する権限がありません。';
    AuraHandledException ex = new AuraHandledException(resolved);
    ex.setMessage(resolved);
    throw ex;
  }

  public static void assertEstimateSave(
    Id editHistoryId,
    Id copyFromHistoryId
  ) {
    assertHas(ESTIMATE, '見積を作成・編集・コピーする権限がありません。');
  }

  /** 仕様: 共通基盤 第10.4節、Core 第4.3.1節。ハブの発行／送付行は04／05。送付3択の読込は03でも04でも05でも可。 */
  public static void assertEstimateDocumentDefaults() {
    if (has(ESTIMATE) || has(ISSUE_ESTIMATE) || has(SEND_ESTIMATE)) {
      return;
    }
    assertHas(ESTIMATE, '見積を作成・編集・コピーする権限がありません。');
  }

  public static void assertArchiveEstimate() {
    assertHas(ESTIMATE, '見積アーカイブを実行する権限がありません。');
  }

  public static void assertOrder() {
    assertHas(ORDER, '受注を実行する権限がありません。');
  }

  public static void assertRevert() {
    assertHas(REVERT, '差し戻しを実行する権限がありません。');
  }

  public static void assertEditService() {
    assertHas(EDIT_SERVICE, '契約サービスを編集する権限がありません。');
  }

  public static void assertViewInvoicePreview() {
    if (canViewInvoiceBoard()) {
      return;
    }
    String message = '請求ボードを表示する権限がありません。';
    AuraHandledException ex = new AuraHandledException(message);
    ex.setMessage(message);
    throw ex;
  }

  public static void assertEditDraftInvoice() {
    assertHas(EDIT_DRAFT_INVOICE, '未確定請求を直す権限がありません。');
  }

  public static void assertConfirmInvoice() {
    assertHas(CONFIRM_INVOICE, '請求を確定する権限がありません。');
  }

  public static void assertSendInvoice() {
    assertHas(SEND_INVOICE, '請求書を発行・送付する権限がありません。');
  }

  public static void assertInvoicePayment() {
    assertHas(INVOICE_PAYMENT, '入金する権限がありません。');
  }

  public static void assertManualJournal() {
    assertHas(MANUAL_JOURNAL, '手動仕訳を実行する権限がありません。');
  }

  public static void assertCancelInvoice() {
    assertHas(CANCEL_INVOICE, '確定済み請求を取り消す権限がありません。');
  }

  public static void assertLockJournal() {
    assertHas(LOCK_JOURNAL, '仕訳をLockする権限がありません。');
  }

  public static void assertUnlockJournal() {
    assertHas(UNLOCK_JOURNAL, '仕訳をUnlockする権限がありません。');
  }

  public static void assertCrossWork() {
    assertHas(CROSS_WORK, '契約横断を開く権限がありません。');
  }

  public static void assertInvoiceOperationKey() {
    if (
      has(EDIT_DRAFT_INVOICE) ||
      has(CONFIRM_INVOICE) ||
      has(INVOICE_PAYMENT) ||
      has(MANUAL_JOURNAL) ||
      has(CANCEL_INVOICE) ||
      has(LOCK_JOURNAL) ||
      has(UNLOCK_JOURNAL)
    ) {
      return;
    }
    assertHas(EDIT_DRAFT_INVOICE, 'この操作を実行する権限がありません。');
  }

  public static void assertOrgSettings() {
    assertHas(ORG_SETTINGS, '組織設定を保存する権限がありません。');
  }

  public static void assertSendEstimates() {
    assertHas(SEND_ESTIMATE, '見積を送る権限がありません。');
  }

  public static void assertIssueEstimate() {
    assertHas(ISSUE_ESTIMATE, '見積書を発行する権限がありません。');
  }
}
