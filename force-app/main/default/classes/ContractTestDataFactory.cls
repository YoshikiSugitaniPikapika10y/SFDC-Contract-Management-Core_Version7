/**
 * 契約管理パッケージのテストデータ組み立て。
 * 必須項目の describe 埋めと、導入先（テナント）固有の制約・候補値もここに集約する。
 * 他社展開時は本クラスの TENANT_* 定数と applyTenantExtraOpportunityFields /
 * テナント固有の商談必須項目・選択リスト値だけを差し替える。
 */
@IsTest
public class ContractTestDataFactory {
  private static User cachedAdminUser;
  private static Boolean permissionSetAssigned = false;
  private static Set<Id> validationEnforceOffOwnerIds = new Set<Id>();
  private static String cachedDefaultStageName;
  private static Id cachedOpportunityRecordTypeId;
  private static Boolean opportunityRecordTypeResolved = false;
  private static final String PERMISSION_SET_NAME = 'Loop_01_Read';

  /**
   * 商談 insert 時に使う StageName 候補（先頭から、組織に存在する最初の値を採用）。
   * 空の場合は OpportunityStage.SortOrder 先頭へフォールバックする。
   * 現行サンプル: PhaseChangedRule 相当（RT=contact_oportunity 時）。
   */
  public static final List<String> TENANT_OPPORTUNITY_INSERT_STAGE_CANDIDATES = new List<String>{
    'S1_ライトパーソンを見極める'
  };

  /**
   * 商談 insert 時に使う RecordType DeveloperName 候補。
   * 空、または見つからない場合は RecordType を設定しない。
   */
  public static final List<String> TENANT_OPPORTUNITY_RECORD_TYPE_DEV_NAME_CANDIDATES = new List<String>{
    'contact_oportunity'
  };

  // ---- 導入先で差し替える選択リスト値（テスト共通）。顧客展開時はここだけ変更する ----
  public static final Integer TENANT_BILLING_DAY_1 = 1;
  public static final Integer TENANT_BILLING_DAY_5 = 5;
  public static final Integer TENANT_BILLING_DAY_15 = 15;
  public static final Integer TENANT_BILLING_DAY_20 = 20;
  public static final Integer TENANT_BILLING_DAY_25 = 25;
  public static final String TENANT_PAYMENT_TERM_MONTH_END = '当月末';
  public static final String TENANT_PAYMENT_TERM_NEXT_MONTH_END = '翌月末';
  public static final String TENANT_BILLING_DAY_SAME_DAY = '即日';

  /** 仕様: Core 第7.2節、第7.5節 */
  public static void applyDefaultBillingSchedule(BillingAccount__c account) {
    if (account == null) {
      return;
    }
    if (String.isBlank(account.InvoiceDateMethod__c)) {
      applyOnOrAfterBillingDay(account, TENANT_BILLING_DAY_25);
    }
    if (String.isBlank(account.PaymentTermMethod__c)) {
      applyPaymentMonthEnd(account, 0);
    }
  }

  public static void applyOnOrAfterBillingDay(
    BillingAccount__c account,
    Integer dayOfMonth
  ) {
    if (account == null) {
      return;
    }
    account.InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER;
    account.InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY;
    account.InvoiceDateDayOfMonth__c = dayOfMonth;
    account.InvoiceDateMonthOffset__c = null;
    account.InvoiceDateDayOffset__c = null;
    account.InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE;
  }

  public static void applySameDayBilling(BillingAccount__c account) {
    if (account == null) {
      return;
    }
    account.InvoiceDateMethod__c = BillingScheduleService.METHOD_SAME_DAY;
    account.InvoiceDateDayKind__c = null;
    account.InvoiceDateDayOfMonth__c = null;
    account.InvoiceDateMonthOffset__c = null;
    account.InvoiceDateDayOffset__c = null;
    account.InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE;
  }

  public static void applyPaymentMonthEnd(
    BillingAccount__c account,
    Integer monthOffset
  ) {
    if (account == null) {
      return;
    }
    account.PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET;
    account.PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END;
    account.PaymentTermDayOfMonth__c = null;
    account.PaymentTermMonthOffset__c = monthOffset;
    account.PaymentTermDayOffset__c = null;
    account.PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE;
  }

  public static void applyPaymentMonthDay(
    BillingAccount__c account,
    Integer monthOffset,
    Integer dayOfMonth
  ) {
    if (account == null) {
      return;
    }
    account.PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET;
    account.PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_DAY;
    account.PaymentTermDayOfMonth__c = dayOfMonth;
    account.PaymentTermMonthOffset__c = monthOffset;
    account.PaymentTermDayOffset__c = null;
    account.PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE;
  }

  public static final String TENANT_INVOICE_TYPE_PREPAID = '一括前払';
  public static final String TENANT_INVOICE_TYPE_MONTHLY = '月次分割';
  public static final String TENANT_BILLING_TYPE_RECURRING = '継続課金';
  public static final String TENANT_BILLING_TYPE_ONE_TIME = '一回課金';
  public static final String TENANT_UNIT_NAME_DEFAULT = '式';
  public static final String TENANT_BILLING_ADDRESSEE_DEFAULT = '株式会社テスト 御中';

  /**
   * 月次期間バリデーションを日付に依存せず通す固定開始日。
   * 終了日は endDateForMonthlyCycles で作る（暦の +N月-1日と混同しない）。
   */
  public static Date stableTermStart() {
    return Date.newInstance(2025, 6, 1);
  }

  /** stableTermStart から months か月の月次終了日（開始日基準の整数月）。 */
  public static Date stableTermEnd(Integer months) {
    return MonthlyBillingPeriodUtil.endDateForMonthlyCycles(
      stableTermStart(),
      months
    );
  }

  public static Date stableTermEnd() {
    return stableTermEnd(12);
  }

  public static User getAdminUser() {
    if (cachedAdminUser == null) {
      cachedAdminUser = [
        SELECT Id
        FROM User
        WHERE IsActive = TRUE AND Profile.PermissionsModifyAllData = TRUE
        LIMIT 1
      ];
    }
    // Setup DML（PSA）を先に runAs で分離してから、非 Setup（Enforce）を触る
    assignPermissionSetIfNeeded(cachedAdminUser.Id);
    ensureOrgDocumentSetting();
    ensureLockExemptSetting();
    ensurePaymentLockExemptSetting();
    ensureJournalLockExemptSetting();
    // runAs(admin) 内の DML に効くよう、admin ユーザー階層で Enforce OFF
    ensureCustomerValidationEnforceOff(cachedAdminUser.Id);
    return cachedAdminUser;
  }

  private static Id currentUserId() {
    return UserInfo.getUserId();
  }

  /**
   * 全テストの @TestSetup から呼ぶ前提。
   * 顧客独自入力規則は ContractValidationEnforce__c.Enforce__c=false で必ず無効化する
   * （org 既定が ON でもテストを壊さない）。
   */
  public static void initTestContext() {
    User admin = getAdminUser();
    // 実行ユーザー＋ admin（runAs 先）の両方で OFF
    ensureCustomerValidationEnforceOff(UserInfo.getUserId());
    ensureCustomerValidationEnforceOff(admin.Id);
    ensureOrgDocumentSetting();
    ensureLockExemptSetting();
    ensurePaymentLockExemptSetting();
    ensureJournalLockExemptSetting();
  }

  /** 仕様: Accounting 第3.1節。組織内1件。無いときはシードを作る。 */
  public static GlAccountingPolicy__c ensureOrgAccountingPolicy() {
    List<GlAccountingPolicy__c> existing = [
      SELECT
        Id,
        Name,
        AccountingEnabled__c,
        RevenueRecognitionBasis__c,
        TaxRecognitionTiming__c,
        MonthlyBucketMethod__c,
        MonthlyRecognitionDatePosition__c,
        RoundingTargetBucket__c,
        FrozenAt__c,
        FrozenBy__c
      FROM GlAccountingPolicy__c
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (!existing.isEmpty()) {
      return existing[0];
    }
    GlAccountingPolicy__c created = GlAccountingPolicyService.newOrgDefault();
    insert created;
    return created;
  }

  /** 仕様: Core 第11.6節。ロック除外が空だと請求更新が落ちる。 */
  public static InvoiceLockExemptFields__c ensureLockExemptSetting() {
    InvoiceLockExemptFields__c existing = InvoiceLockExemptFields__c.getOrgDefaults();
    if (existing != null && existing.Id != null) {
      if (String.isBlank(existing.FieldApiNames__c)) {
        existing.FieldApiNames__c = InvoiceLockUtil.SEED_LOCK_EXEMPT_FIELDS;
        update existing;
      }
      return existing;
    }
    InvoiceLockExemptFields__c setting = new InvoiceLockExemptFields__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      FieldApiNames__c = InvoiceLockUtil.SEED_LOCK_EXEMPT_FIELDS
    );
    insert setting;
    return setting;
  }

  /** 仕様: Core 第11.6節。入出金ロック除外が空だと登録後更新が落ちる。 */
  public static InvoicePaymentLockExemptFields__c ensurePaymentLockExemptSetting() {
    InvoicePaymentLockExemptFields__c existing = InvoicePaymentLockExemptFields__c.getOrgDefaults();
    if (existing != null && existing.Id != null) {
      if (String.isBlank(existing.FieldApiNames__c)) {
        existing.FieldApiNames__c = InvoicePaymentLockUtil.SEED_LOCK_EXEMPT_FIELDS;
        update existing;
      }
      return existing;
    }
    InvoicePaymentLockExemptFields__c setting = new InvoicePaymentLockExemptFields__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      FieldApiNames__c = InvoicePaymentLockUtil.SEED_LOCK_EXEMPT_FIELDS
    );
    insert setting;
    return setting;
  }

  /** 仕様: Core 第11.6節。仕訳ロック除外が空だと Lock 後更新が落ちる。 */
  public static GlJournalLockExemptFields__c ensureJournalLockExemptSetting() {
    GlJournalLockExemptFields__c existing = GlJournalLockExemptFields__c.getOrgDefaults();
    if (existing != null && existing.Id != null) {
      if (String.isBlank(existing.FieldApiNames__c)) {
        existing.FieldApiNames__c = JournalLockService.SEED_LOCK_EXEMPT_FIELDS;
        update existing;
      }
      return existing;
    }
    GlJournalLockExemptFields__c setting = new GlJournalLockExemptFields__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      FieldApiNames__c = JournalLockService.SEED_LOCK_EXEMPT_FIELDS
    );
    insert setting;
    return setting;
  }

  /** 仕様: Core 第11.5節・第4.10節。組織設定が無いと受注・見積初期値が落ちる。 */
  public static ContractDocumentSetting__c ensureOrgDocumentSetting() {
    List<ContractDocumentSetting__c> existing = [
      SELECT
        Id,
        EstimateValidMonths__c,
        DefaultMonthlyCycles__c,
        RenewOpportunityEnabled__c,
        EstimateSendMode__c,
        InvoiceSendMode__c,
        CompanyName__c,
        Address__c,
        InvoiceRegistrationNumber__c,
        BankTransferInfo__c,
        EstimateDefaultDocumentTemplateKey__c,
        InvoiceDefaultDocumentTemplateKey__c,
        EstimateDefaultEmailTemplateApiName__c,
        InvoiceDefaultEmailTemplateApiName__c,
        EstimateOrgWideEmailAddress__c,
        InvoiceOrgWideEmailAddress__c
      FROM ContractDocumentSetting__c
      WHERE SetupOwnerId = :UserInfo.getOrganizationId()
      LIMIT 1
    ];
    if (!existing.isEmpty()) {
      return existing[0];
    }
    ContractDocumentSetting__c setting = new ContractDocumentSetting__c(
      Name = 'OrgDefault',
      SetupOwnerId = UserInfo.getOrganizationId(),
      EstimateValidMonths__c = 1,
      DefaultMonthlyCycles__c = 12,
      RenewOpportunityEnabled__c = true,
      EstimateSendMode__c = 'PdfOnly',
      InvoiceSendMode__c = 'PdfOnly',
      EstimateDefaultDocumentTemplateKey__c = 'StandardEstimate',
      InvoiceDefaultDocumentTemplateKey__c = 'StandardInvoice',
      CompanyName__c = 'テスト発行会社',
      Address__c = 'テスト住所',
      InvoiceRegistrationNumber__c = 'T0000000000000',
      BankTransferInfo__c = 'テスト振込先'
    );
    insert setting;
    ContractDocumentSettingService.clearCache();
    return setting;
  }

  /** 顧客 VR 強制を OFF。組織既定だけを書く（第11.6節。ユーザー階層は使わない）。 */
  public static void ensureCustomerValidationEnforceOff() {
    ensureCustomerValidationEnforceOff(UserInfo.getOrganizationId());
  }

  public static void ensureCustomerValidationEnforceOff(Id setupOwnerId) {
    Id organizationId = UserInfo.getOrganizationId();
    Id ownerId = setupOwnerId == null ? organizationId : setupOwnerId;
    // 仕様: Core 第11.6節。製品は組織既定だけ。引数がユーザーでも Org に寄せる。
    ownerId = organizationId;
    if (validationEnforceOffOwnerIds.contains(ownerId)) {
      return;
    }
    List<ContractValidationEnforce__c> existing = [
      SELECT Id, Enforce__c
      FROM ContractValidationEnforce__c
      WHERE SetupOwnerId = :ownerId
      LIMIT 1
    ];
    if (existing.isEmpty()) {
      insert new ContractValidationEnforce__c(
        SetupOwnerId = ownerId,
        Enforce__c = false
      );
    } else if (existing[0].Enforce__c != false) {
      existing[0].Enforce__c = false;
      update existing[0];
    }
    List<ContractValidationEnforce__c> overrides = [
      SELECT Id
      FROM ContractValidationEnforce__c
      WHERE SetupOwnerId != :organizationId
    ];
    if (!overrides.isEmpty()) {
      delete overrides;
    }
    validationEnforceOffOwnerIds.add(ownerId);
  }

  private static void assignPermissionSetIfNeeded(Id userId) {
    if (permissionSetAssigned) {
      return;
    }
    List<PermissionSet> permissionSets = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = :PERMISSION_SET_NAME
      LIMIT 1
    ];
    if (permissionSets.isEmpty()) {
      return;
    }
    if (
      [
        SELECT COUNT()
        FROM PermissionSetAssignment
        WHERE AssigneeId = :userId AND PermissionSetId = :permissionSets[0].Id
      ] == 0
    ) {
      // Setup / non-Setup の MIXED_DML を避ける（テスト実行経路差でも安定させる）
      System.runAs(new User(Id = UserInfo.getUserId())) {
        insert new PermissionSetAssignment(
          AssigneeId = userId,
          PermissionSetId = permissionSets[0].Id
        );
      }
    }
    permissionSetAssigned = true;
  }

  /**
   * 環境ごとの必須項目（標準・カスタム）をダミー値で埋める。
   * Validation Rule / 依存選択リストまでは解決できないが、
   * describe 上の createable 必須はここで吸収する。
   */
  public static void applyRequiredFields(SObject record) {
    if (record == null) {
      return;
    }
    Schema.SObjectType objectType = record.getSObjectType();
    // InvoiceLine の計上基準は項目定義上は任意だが、正式仕様の VR では必須。
    // テストデータ生成時も本番と同じ既定値を明示し、VR を迂回しない。
    if (
      objectType == InvoiceLine__c.SObjectType &&
      record.get('RevenueRecognitionBasis__c') == null
    ) {
      record.put(
        'RevenueRecognitionBasis__c',
        ContractMetadataService.REVENUE_BASIS_OVER_TIME
      );
    }
    if (objectType == BillingAccount__c.SObjectType) {
      applyDefaultBillingSchedule((BillingAccount__c) record);
    }
    Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe()
      .fields.getMap();
    for (Schema.SObjectField fieldToken : fieldMap.values()) {
      Schema.DescribeFieldResult fieldDescribe = fieldToken.getDescribe();
      if (!isFillableRequiredField(fieldDescribe)) {
        continue;
      }
      String fieldName = fieldDescribe.getName();
      if (record.get(fieldName) != null) {
        continue;
      }
      Object defaultValue = defaultValueFor(fieldDescribe);
      if (defaultValue != null) {
        record.put(fieldName, defaultValue);
      }
    }
  }

  private static Boolean isFillableRequiredField(
    Schema.DescribeFieldResult fieldDescribe
  ) {
    if (
      !fieldDescribe.isCreateable() ||
      fieldDescribe.isNillable() ||
      fieldDescribe.isCalculated() ||
      fieldDescribe.isAutoNumber() ||
      fieldDescribe.isDefaultedOnCreate()
    ) {
      return false;
    }
    Schema.DisplayType fieldType = fieldDescribe.getType();
    if (
      fieldType == Schema.DisplayType.ADDRESS ||
      fieldType == Schema.DisplayType.LOCATION ||
      fieldType == Schema.DisplayType.BASE64 ||
      fieldType == Schema.DisplayType.ID
    ) {
      return false;
    }
    return true;
  }

  private static Object defaultValueFor(
    Schema.DescribeFieldResult fieldDescribe
  ) {
    Schema.DisplayType fieldType = fieldDescribe.getType();
    if (fieldType == Schema.DisplayType.REFERENCE) {
      List<Schema.SObjectType> referenceTypes = fieldDescribe.getReferenceTo();
      for (Schema.SObjectType referenceType : referenceTypes) {
        if (referenceType == User.SObjectType) {
          return currentUserId();
        }
      }
      return null;
    }
    if (fieldType == Schema.DisplayType.BOOLEAN) {
      return false;
    }
    if (
      fieldType == Schema.DisplayType.PICKLIST ||
      fieldType == Schema.DisplayType.MULTIPICKLIST
    ) {
      for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
        if (entry.isActive()) {
          return entry.getValue();
        }
      }
      return null;
    }
    if (fieldType == Schema.DisplayType.DATE) {
      return Date.today();
    }
    if (fieldType == Schema.DisplayType.DATETIME) {
      return System.now();
    }
    if (fieldType == Schema.DisplayType.TIME) {
      return Time.newInstance(12, 0, 0, 0);
    }
    if (
      fieldType == Schema.DisplayType.DOUBLE ||
      fieldType == Schema.DisplayType.CURRENCY ||
      fieldType == Schema.DisplayType.PERCENT ||
      fieldType == Schema.DisplayType.INTEGER ||
      fieldType == Schema.DisplayType.LONG
    ) {
      return 0;
    }
    if (fieldType == Schema.DisplayType.EMAIL) {
      return 'test@example.com';
    }
    if (fieldType == Schema.DisplayType.PHONE) {
      return '0300000000';
    }
    if (fieldType == Schema.DisplayType.URL) {
      return 'https://example.com';
    }
    return 'Test';
  }

  public static Product2 buildProduct(String name) {
    Product2 product = new Product2(
      Name = name,
      IsActive = true,
      // テスト用。本番フィールドのデフォルトは false（運用でON）
      IncludeInARR__c = true
    );
    applyRequiredFields(product);
    return product;
  }

  public static void insertProduct(Product2 product) {
    // テストの ARR 期待値維持のため、明示指定がなければ ARR計算対象 ON
    insertProduct(product, true);
  }

  public static void insertProduct(Product2 product, Boolean includeInArr) {
    applyRequiredFields(product);
    ensureAvailableForContract(product);
    product.IncludeInARR__c = includeInArr == true;
    insert product;
  }

  public static void insertProducts(List<Product2> products) {
    for (Product2 product : products) {
      applyRequiredFields(product);
      ensureAvailableForContract(product);
      product.IncludeInARR__c = true;
    }
    insert products;
  }

  /**
   * AvailableForContract バリデーションを満たす形で契約管理利用可をONにする。
   * 課金形態・請求形態が揃っていない商品は触らない。
   */
  private static void ensureAvailableForContract(Product2 product) {
    if (product == null || product.AvailableForContract__c == true) {
      return;
    }
    if (String.isBlank(product.BillingType__c)) {
      return;
    }
    if (String.isBlank(product.invoicetype__c)) {
      product.invoicetype__c = TENANT_INVOICE_TYPE_PREPAID;
    }
    if (product.UnitPrice__c == null) {
      product.UnitPrice__c = 0;
    }
    if (String.isBlank(product.UnitName__c)) {
      product.UnitName__c = TENANT_UNIT_NAME_DEFAULT;
    }
    if (String.isBlank(product.RevenueRecognitionBasis__c)) {
      product.RevenueRecognitionBasis__c = product.BillingType__c ==
        TENANT_BILLING_TYPE_RECURRING
        ? ContractMetadataService.REVENUE_BASIS_OVER_TIME
        : ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME;
    }
    product.AvailableForContract__c = true;
  }

  public static Account buildAccount(String name) {
    Account account = new Account(Name = name);
    applyRequiredFields(account);
    return account;
  }

  public static Account insertAccount(String name) {
    Account account = buildAccount(name);
    Database.SaveResult saveResult = Database.insert(account, false);
    if (saveResult.isSuccess()) {
      return account;
    }
    // 導入先の Account トリガ破損等で insert できない場合のフォールバック。
    // 同一トランザクション内に既存があれば再利用（検証対象が Account 自体でないケース向け）。
    List<Account> existing = [
      SELECT Id, Name
      FROM Account
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    if (!existing.isEmpty()) {
      return existing[0];
    }
    String message = 'Account insert failed';
    for (Database.Error err : saveResult.getErrors()) {
      message += ': ' + err.getMessage();
    }
    System.assert(false, message);
    return account;
  }

  public static Contact buildContact(Id accountId, String lastName) {
    Contact contact = new Contact(LastName = lastName, AccountId = accountId);
    applyRequiredFields(contact);
    return contact;
  }

  public static Contact insertContact(Id accountId, String lastName) {
    Contact contact = buildContact(accountId, lastName);
    insert contact;
    return contact;
  }

  /** 導入先 VR を通す請求アカウント（送付先メール含む）。 */
  public static BillingAccount__c insertBillingAccount(Id accountId) {
    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = accountId,
      BillingAddressee__c = TENANT_BILLING_ADDRESSEE_DEFAULT,
      BillingEmailTo__c = 'to@example.com',
      BillingEmailCc__c = 'cc@example.com',
      BillingEmailBcc__c = 'bcc@example.com'
    );
    applyDefaultBillingSchedule(billingAccount);
    applyRequiredFields(billingAccount);
    insert billingAccount;
    return billingAccount;
  }

  /**
   * 受注検証を通す契約サービス（BiilingAcccount__c 付き）。
   * Ordered 履歴を作るテストは原則これを使う。
   */
  public static ContractService__c insertContractService(
    Id accountId,
    String name
  ) {
    BillingAccount__c billingAccount = insertBillingAccount(accountId);
    ContractService__c service = new ContractService__c(
      Name = name,
      Account__c = accountId,
      BiilingAcccount__c = billingAccount.Id,
      TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
    );
    applyRequiredFields(service);
    insert service;
    return service;
  }

  public static Opportunity insertOpportunity(Id accountId, String name) {
    return insertOpportunity(accountId, name, null, false, null);
  }

  public static Opportunity insertOpportunity(
    Id accountId,
    String name,
    Id previousOpportunityId,
    Boolean renewEstimateAutoCreate
  ) {
    return insertOpportunity(
      accountId,
      name,
      previousOpportunityId,
      renewEstimateAutoCreate,
      null
    );
  }

  public static Opportunity insertOpportunity(
    Id accountId,
    String name,
    Id previousOpportunityId,
    Boolean renewEstimateAutoCreate,
    Id contractServiceId
  ) {
    Contact contact = insertContact(accountId, 'Test Contact');
    Opportunity opportunity = buildOpportunity(
      accountId,
      name,
      previousOpportunityId,
      renewEstimateAutoCreate,
      contractServiceId
    );
    opportunity.ContactId = contact.Id;
    applyOpportunityDefaults(opportunity);
    insert opportunity;
    return opportunity;
  }

  public static Opportunity buildOpportunity(
    Id accountId,
    String name,
    Id previousOpportunityId,
    Boolean renewEstimateAutoCreate
  ) {
    return buildOpportunity(
      accountId,
      name,
      previousOpportunityId,
      renewEstimateAutoCreate,
      null
    );
  }

  public static Opportunity buildOpportunity(
    Id accountId,
    String name,
    Id previousOpportunityId,
    Boolean renewEstimateAutoCreate,
    Id contractServiceId
  ) {
    Opportunity opportunity = new Opportunity(
      Name = name,
      AccountId = accountId,
      OwnerId = currentUserId(),
      CloseDate = Date.today().addMonths(1)
    );
    Map<String, Schema.SObjectField> opportunityFields = Schema.sObjectType.Opportunity.fields.getMap();
    if (
      previousOpportunityId != null &&
      opportunityFields.containsKey('PreviousOpportunity__c')
    ) {
      opportunity.put('PreviousOpportunity__c', previousOpportunityId);
    }
    applyContractServiceIfPresent(opportunity, contractServiceId);
    applyOpportunityDefaults(opportunity);
    return opportunity;
  }

  private static void applyContractServiceIfPresent(
    Opportunity opportunity,
    Id contractServiceId
  ) {
    if (opportunity == null || contractServiceId == null) {
      return;
    }
    Map<String, Schema.SObjectField> fieldMap = Schema.sObjectType.Opportunity.fields.getMap();
    if (fieldMap.containsKey('ContractService__c')) {
      opportunity.put('ContractService__c', contractServiceId);
    }
  }

  /**
   * 既存テストが new Opportunity(...) している箇所向け。
   * テナント候補の RT / Stage / 必須項目を上書き適用する。
   */
  public static void applyOpportunityDefaults(Opportunity opportunity) {
    if (opportunity == null) {
      return;
    }
    if (opportunity.RecordTypeId == null) {
      Id recordTypeId = resolveOpportunityRecordTypeId();
      if (recordTypeId != null) {
        opportunity.RecordTypeId = recordTypeId;
      }
    }
    opportunity.StageName = resolveDefaultStageName();
    if (opportunity.CloseDate == null) {
      opportunity.CloseDate = Date.today().addMonths(1);
    }
    if (opportunity.OwnerId == null) {
      opportunity.OwnerId = currentUserId();
    }
    applyRequiredFields(opportunity);
    applyTenantExtraOpportunityFields(opportunity);
  }

  /**
   * describe では任意でも、導入先 VR で事実上必須になりやすい商談項目を埋める。
   * 他社で不要ならメソッド本体を空にする。
   */
  public static void applyTenantExtraOpportunityFields(
    Opportunity opportunity
  ) {
    if (opportunity == null) {
      return;
    }
    Map<String, Schema.SObjectField> fieldMap = Schema.sObjectType.Opportunity.fields.getMap();
    if (
      fieldMap.containsKey('OpportunityCreater__c') &&
      opportunity.get('OpportunityCreater__c') == null
    ) {
      opportunity.put('OpportunityCreater__c', UserInfo.getUserId());
    }
    if (
      fieldMap.containsKey('CustomFieldDefinition9__c') &&
      opportunity.get('CustomFieldDefinition9__c') == null
    ) {
      opportunity.put('CustomFieldDefinition9__c', Date.today());
    }
    if (fieldMap.containsKey('OpportunitySequeceNumber__c')) {
      opportunity.put('OpportunitySequeceNumber__c', '1-1_');
      if (
        String.isNotBlank(opportunity.Name) &&
        !Pattern.matches('^[0-9]+-[0-9]+_.*$', opportunity.Name)
      ) {
        opportunity.Name = '1-1_' + opportunity.Name;
      }
    }
    if (fieldMap.containsKey('Product__c')) {
      opportunity.put('Product__c', 'Zeroboard');
    }
    if (fieldMap.containsKey('AccountingDepartment__c')) {
      opportunity.put('AccountingDepartment__c', 'ES');
    }
  }

  public static void applyOpportunityDefaults(List<Opportunity> opportunities) {
    if (opportunities == null) {
      return;
    }
    for (Opportunity opportunity : opportunities) {
      applyOpportunityDefaults(opportunity);
    }
  }

  /**
   * EstimateNoteMaster__c をテナント必須（MatchKey__c 等）込みで作成する。
   */
  public static EstimateNoteMaster__c insertEstimateNoteMaster(
    String name,
    String noteText
  ) {
    EstimateNoteMaster__c master = new EstimateNoteMaster__c(
      Name = name,
      NoteText__c = noteText
    );
    applyRequiredFields(master);
    Map<String, Schema.SObjectField> fieldMap = Schema.sObjectType.EstimateNoteMaster__c.fields.getMap();
    if (fieldMap.containsKey('MatchKey__c')) {
      Object current = master.get('MatchKey__c');
      if (current == null || String.valueOf(current) == 'Test') {
        master.put(
          'MatchKey__c',
          'MK-' + String.valueOf(Crypto.getRandomLong()).replace('-', 'N')
        );
      }
    }
    insert master;
    return master;
  }

  private static Id resolveOpportunityRecordTypeId() {
    if (opportunityRecordTypeResolved) {
      return cachedOpportunityRecordTypeId;
    }
    opportunityRecordTypeResolved = true;
    List<String> candidates = TENANT_OPPORTUNITY_RECORD_TYPE_DEV_NAME_CANDIDATES;
    if (candidates == null || candidates.isEmpty()) {
      cachedOpportunityRecordTypeId = null;
      return null;
    }
    Map<String, Schema.RecordTypeInfo> infoByDevName = Schema.sObjectType.Opportunity.getRecordTypeInfosByDeveloperName();
    for (String candidate : candidates) {
      if (String.isBlank(candidate)) {
        continue;
      }
      Schema.RecordTypeInfo info = infoByDevName.get(candidate);
      if (info != null && info.isAvailable()) {
        cachedOpportunityRecordTypeId = info.getRecordTypeId();
        return cachedOpportunityRecordTypeId;
      }
    }
    cachedOpportunityRecordTypeId = null;
    return null;
  }

  /**
   * 環境ごとのフェーズ名差を吸収する。
   * 1) TENANT_OPPORTUNITY_INSERT_STAGE_CANDIDATES の候補（存在する値のみ）
   * 2) 未クローズの OpportunityStage（SortOrder昇順）
   * 3) アクティブな StageName ピックリスト先頭
   */
  public static String resolveDefaultStageName() {
    if (cachedDefaultStageName != null) {
      return cachedDefaultStageName;
    }

    Set<String> activeStageValues = new Set<String>();
    for (
      Schema.PicklistEntry entry : Opportunity.StageName.getDescribe()
        .getPicklistValues()
    ) {
      if (entry.isActive() && String.isNotBlank(entry.getValue())) {
        activeStageValues.add(entry.getValue());
      }
    }

    List<String> preferred = TENANT_OPPORTUNITY_INSERT_STAGE_CANDIDATES;
    if (preferred != null) {
      for (String candidate : preferred) {
        if (
          String.isNotBlank(candidate) && activeStageValues.contains(candidate)
        ) {
          cachedDefaultStageName = candidate;
          return cachedDefaultStageName;
        }
      }
    }

    for (OpportunityStage stage : [
      SELECT ApiName, MasterLabel
      FROM OpportunityStage
      WHERE IsActive = TRUE AND IsClosed = FALSE
      ORDER BY SortOrder ASC
      LIMIT 1
    ]) {
      if (
        String.isNotBlank(stage.ApiName) &&
        activeStageValues.contains(stage.ApiName)
      ) {
        cachedDefaultStageName = stage.ApiName;
        return cachedDefaultStageName;
      }
      if (
        String.isNotBlank(stage.MasterLabel) &&
        activeStageValues.contains(stage.MasterLabel)
      ) {
        cachedDefaultStageName = stage.MasterLabel;
        return cachedDefaultStageName;
      }
    }

    for (String stageValue : activeStageValues) {
      cachedDefaultStageName = stageValue;
      return cachedDefaultStageName;
    }

    cachedDefaultStageName = 'Prospecting';
    return cachedDefaultStageName;
  }

  /** U-ZERO 本番向け: Sample CMDT に依存せずウィザード項目をテストする。 */
  public static final String WIZARD_TEST_PRODUCT_FAMILY = 'TestFamily';

  public static void applyStandardWizardFieldDefinitionsForTest() {
    ContractWizardFieldService.resetCache();
    ContractWizardFieldService.setCachedDefinitionsForTest(
      new List<EstimateWizardField__mdt>{
        new EstimateWizardField__mdt(
          DeveloperName = 'Test_Service_CustomerMemo',
          MasterLabel = 'Test Service Memo',
          Active__c = true,
          TargetObject__c = 'ContractService__c',
          FieldApiName__c = 'CustomerMemo__c',
          SortOrder__c = 10,
          ShowOnNew__c = true,
          ShowOnChange__c = true,
          ShowOnRenew__c = true,
          ShowOnCancel__c = true
        ),
        new EstimateWizardField__mdt(
          DeveloperName = 'Test_History_ApplicationDate',
          MasterLabel = 'Test Application Date',
          Active__c = true,
          TargetObject__c = 'ContractHistory__c',
          FieldApiName__c = 'ApplicationDate__c',
          SortOrder__c = 10,
          ShowOnNew__c = true,
          ShowOnChange__c = true,
          ShowOnRenew__c = true,
          ShowOnCancel__c = true
        ),
        new EstimateWizardField__mdt(
          DeveloperName = 'Test_Product_Description',
          MasterLabel = 'Test Product Description',
          Active__c = true,
          TargetObject__c = 'ContractProduct__c',
          FieldApiName__c = 'Description__c',
          DefaultValue__c = 'サンプルデフォルトメモ',
          SortOrder__c = 10,
          ShowOnNew__c = true,
          ShowOnChange__c = true,
          ShowOnRenew__c = true,
          ShowOnCancel__c = true,
          VisibilityFieldApiName__c = 'Family',
          VisibilityOperator__c = 'EQUALS',
          VisibilityValues__c = WIZARD_TEST_PRODUCT_FAMILY
        )
      }
    );
  }

  public static void insertAllowingInvoiceStatus(Invoice__c invoice) {
    insertAllowingInvoiceStatus(new List<Invoice__c>{ invoice });
  }

  public static void insertAllowingInvoiceStatus(List<Invoice__c> invoices) {
    Boolean previous = InvoiceTransactionStatusService.allowStatusWrite;
    InvoiceTransactionStatusService.allowStatusWrite = true;
    try {
      insert invoices;
    } finally {
      InvoiceTransactionStatusService.allowStatusWrite = previous;
    }
  }
}
