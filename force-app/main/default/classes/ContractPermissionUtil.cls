/**
 * 操作別カスタム権限（04〜14）の判定・assert を集約する。
 * テストでは 04〜13 はデフォルト許可。99（整合性バイパス）はデフォルト拒否。
 * 99 は例外処理専用（通常業務の連番には使わない）。
 */
public without sharing class ContractPermissionUtil {
  public static final String CREATE_ESTIMATE = 'Contract_04_Can_Create_Estimate';
  public static final String EDIT_ESTIMATE = 'Contract_05_Can_Edit_Estimate';
  public static final String COPY_ESTIMATE = 'Contract_06_Can_Copy_Estimate';
  public static final String ARCHIVE_ESTIMATE = 'Contract_07_Can_Archive_Estimate';
  public static final String ISSUE_ESTIMATE_DOCUMENT = 'Contract_08_Can_Issue_Estimate_Document';
  public static final String ORDER = 'Contract_09_Can_Order';
  public static final String REVERT = 'Contract_10_Can_Revert';
  public static final String VIEW_INVOICE_PREVIEW = 'Contract_11_Can_View_Invoice_Preview';
  public static final String EDIT_INVOICE_PREVIEW = 'Contract_12_Can_Edit_Invoice_Preview';
  public static final String MANAGE_INVOICE_OPS = 'Contract_13_Can_Manage_Invoice_Ops';
  public static final String BYPASS_INTEGRITY = 'Contract_99_Can_Bypass_Integrity_Guards';

  /** テスト既定: 04〜13 は許可。false にすると未オーバーライド分も拒否。 */
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
      // 整合性バイパスはテスト既定 OFF（ガード検証を壊さない）
      if (permissionName == BYPASS_INTEGRITY) {
        return false;
      }
      return testAllowAll != false;
    }
    return FeatureManagement.checkPermission(permissionName);
  }

  /** 緊急時の整合性ガード解除（#99）。通常は付与しない。 */
  public static Boolean canBypassIntegrityGuards() {
    return has(BYPASS_INTEGRITY);
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
    if (editHistoryId != null) {
      assertHas(EDIT_ESTIMATE, '見積編集を実行する権限がありません。');
    } else if (copyFromHistoryId != null) {
      assertHas(COPY_ESTIMATE, '見積コピーを実行する権限がありません。');
    } else {
      assertHas(CREATE_ESTIMATE, '見積作成を実行する権限がありません。');
    }
  }

  public static void assertArchiveEstimate() {
    assertHas(ARCHIVE_ESTIMATE, '見積アーカイブを実行する権限がありません。');
  }

  public static void assertOrder() {
    assertHas(ORDER, '受注を実行する権限がありません。');
  }

  public static void assertRevert() {
    assertHas(REVERT, '差し戻しを実行する権限がありません。');
  }

  public static void assertViewInvoicePreview() {
    assertHas(
      VIEW_INVOICE_PREVIEW,
      '請求プレビューを表示する権限がありません。'
    );
  }

  public static void assertManageInvoiceOps() {
    assertHas(
      MANAGE_INVOICE_OPS,
      '請求の連携・消込操作を実行する権限がありません。'
    );
  }
}
