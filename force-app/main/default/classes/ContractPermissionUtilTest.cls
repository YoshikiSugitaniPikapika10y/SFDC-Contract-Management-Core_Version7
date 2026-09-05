@IsTest
private class ContractPermissionUtilTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void has_defaultsAllowOperations_andDeniesIrregular() {
    System.assertEquals(
      true,
      ContractPermissionUtil.has(ContractPermissionUtil.ORDER)
    );
    System.assertEquals(
      false,
      ContractPermissionUtil.hasMigrateAll()
    );
    System.assertEquals(
      true,
      ContractPermissionUtil.has(ContractPermissionUtil.CONFIRM_INVOICE)
    );

    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.ORDER => false,
      ContractPermissionUtil.MIGRATE_ALL => true
    };
    System.assertEquals(
      false,
      ContractPermissionUtil.has(ContractPermissionUtil.ORDER)
    );
    System.assertEquals(
      true,
      ContractPermissionUtil.hasMigrateAll()
    );

    ContractPermissionUtil.testOverrides = null;
    ContractPermissionUtil.testAllowAll = false;
    System.assertEquals(
      false,
      ContractPermissionUtil.has(ContractPermissionUtil.ORDER)
    );
    ContractPermissionUtil.testAllowAll = true;
  }

  @IsTest
  static void assertEstimateSave_uses03ForCreateEditCopy() {
    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.ESTIMATE => false
    };

    Boolean createBlocked = false;
    try {
      ContractPermissionUtil.assertEstimateSave(null, null);
    } catch (AuraHandledException ex) {
      createBlocked = true;
    }
    System.assertEquals(true, createBlocked);

    Boolean editBlocked = false;
    try {
      ContractPermissionUtil.assertEstimateSave(UserInfo.getUserId(), null);
    } catch (AuraHandledException ex) {
      editBlocked = true;
    }
    System.assertEquals(true, editBlocked);

    Boolean copyBlocked = false;
    try {
      ContractPermissionUtil.assertEstimateSave(null, UserInfo.getUserId());
    } catch (AuraHandledException ex) {
      copyBlocked = true;
    }
    System.assertEquals(true, copyBlocked);

    ContractPermissionUtil.testOverrides = null;
  }

  @IsTest
  static void issuePdf_blocksWithoutPermission() {
    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.ISSUE_ESTIMATE => false
    };
    PageReference issuePage = Page.EstimateDocumentIssue;
    issuePage.getParameters().put('id', UserInfo.getUserId());
    Test.setCurrentPage(issuePage);
    EstimateDocumentPdfController controller = new EstimateDocumentPdfController();
    PageReference result = controller.issuePdf();
    ContractPermissionUtil.testOverrides = null;
    System.assertEquals(null, result);
    System.assertEquals(true, ApexPages.hasMessages());
  }

  @IsTest
  static void assertConfirmInvoice_andSiblingAsserts() {
    ContractPermissionUtil.assertConfirmInvoice();
    ContractPermissionUtil.assertOrder();
    ContractPermissionUtil.assertRevert();
    ContractPermissionUtil.assertViewInvoicePreview();
    ContractPermissionUtil.assertArchiveEstimate();

    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.CONFIRM_INVOICE => false
    };
    Boolean blocked = false;
    try {
      ContractPermissionUtil.assertConfirmInvoice();
    } catch (AuraHandledException ex) {
      blocked = true;
      System.assertEquals(
        '請求を確定する権限がありません。',
        ex.getMessage()
      );
    } finally {
      ContractPermissionUtil.testOverrides = null;
    }
    System.assertEquals(true, blocked);

    ContractPermissionUtil.assertHas(
      ContractPermissionUtil.CONFIRM_INVOICE,
      null
    );
  }

  @IsTest
  static void postEstimatePermissionGates_throwExactMessages() {
    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.ORDER => false
    };
    try {
      Boolean blocked = false;
      try {
        ContractPermissionUtil.assertOrder();
      } catch (AuraHandledException ex) {
        blocked = true;
        System.assertEquals(
          '受注を実行する権限がありません。',
          ex.getMessage()
        );
      }
      System.assertEquals(true, blocked);
    } finally {
      ContractPermissionUtil.testOverrides = null;
    }

    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.REVERT => false
    };
    try {
      Boolean blocked = false;
      try {
        ContractPermissionUtil.assertRevert();
      } catch (AuraHandledException ex) {
        blocked = true;
        System.assertEquals(
          '差し戻しを実行する権限がありません。',
          ex.getMessage()
        );
      }
      System.assertEquals(true, blocked);
    } finally {
      ContractPermissionUtil.testOverrides = null;
    }

    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.ESTIMATE => false
    };
    try {
      Boolean blocked = false;
      try {
        ContractPermissionUtil.assertArchiveEstimate();
      } catch (AuraHandledException ex) {
        blocked = true;
        System.assertEquals(
          '見積アーカイブを実行する権限がありません。',
          ex.getMessage()
        );
      }
      System.assertEquals(true, blocked);
    } finally {
      ContractPermissionUtil.testOverrides = null;
    }

    ContractPermissionUtil.testAllowAll = false;
    try {
      Boolean blocked = false;
      try {
        ContractPermissionUtil.assertViewInvoicePreview();
      } catch (AuraHandledException ex) {
        blocked = true;
        System.assertEquals(
          '請求ボードを表示する権限がありません。',
          ex.getMessage()
        );
      }
      System.assertEquals(true, blocked);
    } finally {
      ContractPermissionUtil.testAllowAll = true;
    }

    ContractPermissionUtil.testAllowAll = false;
    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.EDIT_DRAFT_INVOICE => true
    };
    try {
      ContractPermissionUtil.assertViewInvoicePreview();
    } finally {
      ContractPermissionUtil.testOverrides = null;
      ContractPermissionUtil.testAllowAll = true;
    }
  }

  @IsTest
  static void estimatePresets_blockWithoutPermission() {
    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.ESTIMATE => false
    };
    Boolean editBlocked = false;
    try {
      EstimateCreateController.getEstimateEditPreset(UserInfo.getUserId());
    } catch (AuraHandledException ex) {
      editBlocked = true;
    }
    Boolean copyBlocked = false;
    try {
      EstimateCreateController.getEstimateCopyPreset(UserInfo.getUserId());
    } catch (AuraHandledException ex) {
      copyBlocked = true;
    } finally {
      ContractPermissionUtil.testOverrides = null;
    }
    System.assertEquals(true, editBlocked);
    System.assertEquals(true, copyBlocked);
  }

  @IsTest
  static void viewInvoice_allowsTenThroughSeventeenWithout09() {
    ContractPermissionUtil.testAllowAll = false;
    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.CANCEL_INVOICE => true
    };
    try {
      ContractPermissionUtil.assertViewInvoicePreview();
    } finally {
      ContractPermissionUtil.testOverrides = null;
      ContractPermissionUtil.testAllowAll = true;
    }
  }

  @IsTest
  static void hasDeleteRecords_includes104Alone() {
    System.assertEquals(
      false,
      ContractPermissionUtil.hasDeleteRecords(),
      '共通基盤 第3.6節: テスト既定は 103／101 とも拒否'
    );
    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.MIGRATE_ALL => true
    };
    try {
      System.assertEquals(
        true,
        ContractPermissionUtil.hasDeleteRecords(),
        '共通基盤 第3.6節: 101 は 103 を含む'
      );
      System.assertEquals(true, ContractPermissionUtil.hasMigrateAll());
      System.assertEquals(
        false,
        ContractPermissionUtil.has(ContractPermissionUtil.DELETE_RECORDS),
        '共通基盤 第3.6節: 101 単独では 103 カスタム権限は不要'
      );
    } finally {
      ContractPermissionUtil.testOverrides = null;
    }
  }

  @IsTest
  static void has_blankIsFalse_and104Includes101And102() {
    System.assertEquals(
      false,
      ContractPermissionUtil.has(null),
      '共通基盤 第3.2節: 空の権限名は操作できない'
    );
    System.assertEquals(false, ContractPermissionUtil.hasFixContract());
    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.MIGRATE_ALL => true
    };
    try {
      System.assertEquals(
        true,
        ContractPermissionUtil.hasMigrateAll(),
        '共通基盤 第3.6節: 101 は移行の全部操作'
      );
      System.assertEquals(
        true,
        ContractPermissionUtil.hasFixContract(),
        '共通基盤 第3.6節: 101 は 102 を含む'
      );
    } finally {
      ContractPermissionUtil.testOverrides = null;
    }
  }

  @IsTest
  static void estimateDocumentDefaults_allow03or04or05() {
    ContractPermissionUtil.testAllowAll = false;
    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.ISSUE_ESTIMATE => true
    };
    try {
      ContractPermissionUtil.assertEstimateDocumentDefaults();
    } finally {
      ContractPermissionUtil.testOverrides = null;
      ContractPermissionUtil.testAllowAll = true;
    }

    ContractPermissionUtil.testAllowAll = false;
    Boolean blocked = false;
    try {
      ContractPermissionUtil.assertEstimateDocumentDefaults();
    } catch (AuraHandledException ex) {
      blocked = true;
      System.assertEquals(
        '見積を作成・編集・コピーする権限がありません。',
        ex.getMessage(),
        '共通基盤 第10.4節: 送付3択の読込は 03・04・05 のどれか'
      );
    } finally {
      ContractPermissionUtil.testAllowAll = true;
    }
    System.assertEquals(true, blocked);
  }

  @IsTest
  static void invoiceOperationKey_andEditService_useExactMessages() {
    ContractPermissionUtil.testAllowAll = false;
    Boolean keyBlocked = false;
    try {
      ContractPermissionUtil.assertInvoiceOperationKey();
    } catch (AuraHandledException ex) {
      keyBlocked = true;
      System.assertEquals('この操作を実行する権限がありません。', ex.getMessage());
    } finally {
      ContractPermissionUtil.testAllowAll = true;
    }
    System.assertEquals(true, keyBlocked);

    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.EDIT_SERVICE => false
    };
    Boolean editBlocked = false;
    try {
      ContractPermissionUtil.assertEditService();
    } catch (AuraHandledException ex) {
      editBlocked = true;
      System.assertEquals(
        '契約サービスを編集する権限がありません。',
        ex.getMessage(),
        '共通基盤 第10.4節: 契約サービス保存は 08'
      );
    } finally {
      ContractPermissionUtil.testOverrides = null;
    }
    System.assertEquals(true, editBlocked);
  }

  /** 仕様: 共通基盤 第3.4節・第3.6節。101 の操作ログは Create と Edit を付けない。 */
  @IsTest
  static void migrateAll_operationLogHasNoCreateOrEdit() {
    List<ObjectPermissions> rows = [
      SELECT
        PermissionsCreate,
        PermissionsEdit,
        PermissionsDelete,
        PermissionsRead,
        PermissionsViewAllRecords,
        PermissionsModifyAllRecords
      FROM ObjectPermissions
      WHERE Parent.Name = 'Loop_101_MigrateAll'
        AND SobjectType = 'ContractOperationLog__c'
    ];
    System.assertEquals(
      1,
      rows.size(),
      '共通基盤 第3.4節: 101 に操作ログのオブジェクト権限がある'
    );
    System.assertEquals(false, rows[0].PermissionsCreate);
    System.assertEquals(false, rows[0].PermissionsEdit);
    System.assertEquals(true, rows[0].PermissionsRead);
    System.assertEquals(true, rows[0].PermissionsDelete);
    System.assertEquals(true, rows[0].PermissionsViewAllRecords);
    System.assertEquals(true, rows[0].PermissionsModifyAllRecords);
  }
}
