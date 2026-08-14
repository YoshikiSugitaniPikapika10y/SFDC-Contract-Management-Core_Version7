@IsTest
private class ContractPermissionUtilTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void has_defaultsAllowInTests_andHonorsOverrides() {
    System.assertEquals(
      true,
      ContractPermissionUtil.has(ContractPermissionUtil.ORDER)
    );
    // #99 はテスト既定 OFF
    System.assertEquals(
      false,
      ContractPermissionUtil.canBypassIntegrityGuards()
    );
    // #13 請求Opsはテスト既定 ON（04〜13）
    System.assertEquals(
      true,
      ContractPermissionUtil.has(ContractPermissionUtil.MANAGE_INVOICE_OPS)
    );

    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.ORDER => false,
      ContractPermissionUtil.BYPASS_INTEGRITY => true
    };
    System.assertEquals(
      false,
      ContractPermissionUtil.has(ContractPermissionUtil.ORDER)
    );
    System.assertEquals(
      true,
      ContractPermissionUtil.canBypassIntegrityGuards()
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
  static void assertEstimateSave_routesByIds() {
    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.CREATE_ESTIMATE => false,
      ContractPermissionUtil.EDIT_ESTIMATE => false,
      ContractPermissionUtil.COPY_ESTIMATE => false
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
      ContractPermissionUtil.ISSUE_ESTIMATE_DOCUMENT => false
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
  static void assertManageInvoiceOps_andSiblingAsserts() {
    ContractPermissionUtil.assertManageInvoiceOps();
    ContractPermissionUtil.assertOrder();
    ContractPermissionUtil.assertRevert();
    ContractPermissionUtil.assertViewInvoicePreview();
    ContractPermissionUtil.assertArchiveEstimate();

    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.MANAGE_INVOICE_OPS => false
    };
    Boolean blocked = false;
    try {
      ContractPermissionUtil.assertManageInvoiceOps();
    } catch (AuraHandledException ex) {
      blocked = true;
      System.assertEquals(
        '請求の連携・消込操作を実行する権限がありません。',
        ex.getMessage()
      );
    } finally {
      ContractPermissionUtil.testOverrides = null;
    }
    System.assertEquals(true, blocked);

    ContractPermissionUtil.assertHas(
      ContractPermissionUtil.MANAGE_INVOICE_OPS,
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
      ContractPermissionUtil.ARCHIVE_ESTIMATE => false
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

    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.VIEW_INVOICE_PREVIEW => false
    };
    try {
      Boolean blocked = false;
      try {
        ContractPermissionUtil.assertViewInvoicePreview();
      } catch (AuraHandledException ex) {
        blocked = true;
        System.assertEquals(
          '請求プレビューを表示する権限がありません。',
          ex.getMessage()
        );
      }
      System.assertEquals(true, blocked);
    } finally {
      ContractPermissionUtil.testOverrides = null;
    }
  }

  @IsTest
  static void estimatePresets_blockWithoutPermission() {
    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.EDIT_ESTIMATE => false,
      ContractPermissionUtil.COPY_ESTIMATE => false
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
}
