/**
 * Estimate save validation (New/Change/Renew/Cancel).
 */
public without sharing class EstimateValidationService {
  private static final String HISTORY_STATUS_ESTIMATE = ContractDomainConstants.HISTORY_STATUS_ESTIMATE;
  private static final String HISTORY_STATUS_ARCHIVE = ContractDomainConstants.HISTORY_STATUS_ARCHIVE;
  private static final String HISTORY_STATUS_ORDERED = ContractDomainConstants.HISTORY_STATUS_ORDERED;
  private static final String HISTORY_TYPE_NEW = ContractDomainConstants.HISTORY_TYPE_NEW;
  private static final String HISTORY_TYPE_CHANGE = ContractDomainConstants.HISTORY_TYPE_CHANGE;
  private static final String HISTORY_TYPE_RENEW = ContractDomainConstants.HISTORY_TYPE_RENEW;
  private static final String HISTORY_TYPE_CANCEL = ContractDomainConstants.HISTORY_TYPE_CANCEL;
  private static final String HISTORY_TYPE_ADD = ContractDomainConstants.HISTORY_TYPE_ADD;
  private static final String BILLING_TYPE_RECURRING = ContractDomainConstants.BILLING_TYPE_RECURRING;
  private static final String BILLING_TYPE_ONE_TIME = ContractDomainConstants.BILLING_TYPE_ONE_TIME;
  private static final String MONTHLY_BILLING_CYCLE = ContractDomainConstants.MONTHLY_BILLING_CYCLE;
  private static final String PRODUCT_TYPE_ORIGINAL = ContractDomainConstants.PRODUCT_TYPE_ORIGINAL;
  private static final String PRODUCT_TYPE_REMAKE = ContractDomainConstants.PRODUCT_TYPE_REMAKE;
  private static final String LEGACY_PRODUCT_TYPE_DERIVATIVE = ContractDomainConstants.LEGACY_PRODUCT_TYPE_DERIVATIVE;
  private static final String PRODUCT_TYPE_NEW = ContractDomainConstants.PRODUCT_TYPE_NEW;
  private static final String PRODUCT_TYPE_RENEW = ContractDomainConstants.PRODUCT_TYPE_RENEW;
  private static final Integer NOTE_MAX_LENGTH = ContractDomainConstants.NOTE_MAX_LENGTH;
  private static final String EST_S3_NEW_PREFIX = 'EST-S3-New';
  private static final String EST_S3_RENEW_PREFIX = 'EST-S3-Renew';
  @TestVisible
  private static final String LIFECYCLE_UNASSIGNED_MESSAGE = 'ライフサイクルが未設定です。先にバックフィルしてください。';

  @TestVisible
  private static final String CHANGE_REQUIRES_BILLING_EVENT_MESSAGE = '前回Versionの期間内に課金変更（新規・変更・相殺）がないため、ChangeではなくRenewで作成してください。';

  @TestVisible
  private static final String CHANGE_EFFECTIVE_DATE_BILLING_PERIOD_START_MESSAGE = '切替日は契約開始日基準の請求期間開始日である必要があります（日割りはできません）。';

  @TestVisible
  private static final String CHANGE_REMAKE_COVERAGE_MESSAGE = 'Remake は Originalの期間を重複や隙間なく埋める必要があります。';

  public class ChangeConsistencyException extends Exception {
  }

  /**
   * 請求生成前に、永続化された Change 履歴がウィザード保存ルールと一致するか検証する。
   * 移行データ・画面外 DML で不正な構成が残っている場合にここで止める。
   */
  public static void assertChangeHistoriesReadyForInvoice(
    Set<Id> contractHistoryIds
  ) {
    if (contractHistoryIds == null || contractHistoryIds.isEmpty()) {
      return;
    }

    List<ContractHistory__c> changeHistories = [
      SELECT
        Id,
        Type__c,
        EffectiveDate__c,
        CurrentTermStartDate__c,
        CurrentTermEndDate__c,
        ContractService__c,
        PreviousHistory__c
      FROM ContractHistory__c
      WHERE Id IN :contractHistoryIds AND Type__c = :HISTORY_TYPE_CHANGE
      WITH SYSTEM_MODE
    ];
    if (changeHistories.isEmpty()) {
      return;
    }

    Set<Id> changeHistoryIds = new Set<Id>();
    for (ContractHistory__c history : changeHistories) {
      changeHistoryIds.add(history.Id);
    }

    Map<Id, List<ContractProduct__c>> productsByHistoryId = new Map<Id, List<ContractProduct__c>>();
    for (ContractProduct__c contractProduct : [
      SELECT
        Id,
        ContractHistory__c,
        Product__c,
        Quantity__c,
        UnitPrice__c,
        StartDate__c,
        Enddate__c,
        InvoiceSetting__c,
        BillingType__c,
        Type__c,
        PreviousContractProduct__c
      FROM ContractProduct__c
      WHERE ContractHistory__c IN :changeHistoryIds
      WITH SYSTEM_MODE
      ORDER BY StartDate__c ASC NULLS LAST, Name ASC
    ]) {
      if (
        !productsByHistoryId.containsKey(contractProduct.ContractHistory__c)
      ) {
        productsByHistoryId.put(
          contractProduct.ContractHistory__c,
          new List<ContractProduct__c>()
        );
      }
      productsByHistoryId.get(contractProduct.ContractHistory__c)
        .add(contractProduct);
    }

    for (ContractHistory__c history : changeHistories) {
      assertPersistedChangeHistoryReadyForInvoice(
        history,
        productsByHistoryId.get(history.Id)
      );
    }
  }

  @TestVisible
  private static void assertPersistedChangeHistoryReadyForInvoice(
    ContractHistory__c history,
    List<ContractProduct__c> contractProducts
  ) {
    if (history == null) {
      return;
    }
    if (history.PreviousHistory__c == null) {
      throw new ChangeConsistencyException(
        'Change の前回契約履歴が設定されていないため請求を生成できません。'
      );
    }

    EstimateCreateController.EstimateSaveRequest request = new EstimateCreateController.EstimateSaveRequest();
    request.selectedType = HISTORY_TYPE_CHANGE;
    request.previousHistoryId = history.PreviousHistory__c;
    request.contractServiceId = history.ContractService__c;
    request.contractStartDate = EstimateCreateSupport.formatDate(
      history.CurrentTermStartDate__c
    );
    request.contractEndDate = EstimateCreateSupport.formatDate(
      history.CurrentTermEndDate__c
    );
    request.effectiveDate = EstimateCreateSupport.formatDate(
      history.EffectiveDate__c
    );
    request.products = toProductLineItemsForChangeValidation(contractProducts);

    ContractHistory__c previousHistory = loadPreviousHistoryTerm(
      request.previousHistoryId
    );
    if (previousHistory.Type__c == HISTORY_TYPE_CANCEL) {
      throw new ChangeConsistencyException(
        'Churn（解約）済みの契約履歴からChangeは作成できません。'
      );
    }
    if (!EstimateQueryService.isRenewEligibleHistory(previousHistory)) {
      throw new ChangeConsistencyException(
        '前回Versionの期間終了日と一致する継続課金商品がないためChangeできません。'
      );
    }
    if (
      previousHistory.CurrentTermStartDate__c == null ||
      previousHistory.CurrentTermEndDate__c == null
    ) {
      throw new ChangeConsistencyException(
        '前回契約履歴の期間開始日または期間終了日が取得できません。'
      );
    }

    Date headerStartDate = EstimateCreateSupport.parseDate(
      request.contractStartDate
    );
    Date headerEndDate = EstimateCreateSupport.parseDate(
      request.contractEndDate
    );
    if (headerStartDate != previousHistory.CurrentTermStartDate__c) {
      throw new ChangeConsistencyException(
        '期間開始日は前回Versionの期間開始日と一致している必要があります。'
      );
    }
    if (
      headerEndDate == null ||
      headerEndDate < previousHistory.CurrentTermEndDate__c
    ) {
      throw new ChangeConsistencyException(
        '期間終了日は前回Versionの期間終了日以降の日付を入力してください。'
      );
    }

    List<ContractProduct__c> sourceProducts = loadChangeSourceProducts(
      request.previousHistoryId
    );
    Map<Id, ContractProduct__c> sourceById = new Map<Id, ContractProduct__c>(
      sourceProducts
    );
    Map<Id, EstimateCreateController.ProductLineItem> originalBySourceId = new Map<Id, EstimateCreateController.ProductLineItem>();
    Map<Id, List<EstimateCreateController.ProductLineItem>> remakesBySourceId = new Map<Id, List<EstimateCreateController.ProductLineItem>>();

    for (EstimateCreateController.ProductLineItem line : request.products) {
      line.recordType = EstimateCreateSupport.normalizeProductRecordType(
        line.recordType
      );
      if (EstimateCreateSupport.isChangeOriginalLine(line)) {
        if (line.sourceContractProductId == null) {
          throw new ChangeConsistencyException(
            'Original行に元の見積商品が指定されていません。'
          );
        }
        if (originalBySourceId.containsKey(line.sourceContractProductId)) {
          throw new ChangeConsistencyException('Original行が重複しています。');
        }
        ContractProduct__c source = sourceById.get(
          line.sourceContractProductId
        );
        if (source == null) {
          throw new ChangeConsistencyException(
            'Original行は前回Versionの見積商品と一致している必要があります。'
          );
        }
        originalBySourceId.put(line.sourceContractProductId, line);
        continue;
      }
      if (EstimateCreateSupport.isChangeRemakeLine(line)) {
        if (line.sourceContractProductId == null) {
          throw new ChangeConsistencyException(
            'Remake行に元の見積商品が指定されていません。'
          );
        }
        if (!remakesBySourceId.containsKey(line.sourceContractProductId)) {
          remakesBySourceId.put(
            line.sourceContractProductId,
            new List<EstimateCreateController.ProductLineItem>()
          );
        }
        remakesBySourceId.get(line.sourceContractProductId).add(line);
      }
    }

    for (ContractProduct__c source : sourceProducts) {
      if (!originalBySourceId.containsKey(source.Id)) {
        throw new ChangeConsistencyException(
          '前回Versionの継続課金商品すべてにOriginal行が必要です。'
        );
      }
      List<EstimateCreateController.ProductLineItem> remakes = remakesBySourceId.get(
        source.Id
      );
      if (remakes == null || remakes.isEmpty()) {
        throw new ChangeConsistencyException(
          '前回Versionの継続課金商品すべてにRemake行を1件以上入力してください。'
        );
      }
      String reconstitutionError = validateChangeReconstitutionCoverage(
        originalBySourceId.get(source.Id),
        remakes
      );
      if (reconstitutionError != null) {
        throw new ChangeConsistencyException(reconstitutionError);
      }
    }

    Date effectiveDate = EstimateCreateSupport.parseDate(request.effectiveDate);
    Date expectedEffectiveDate = getEarliestChangeBillingThresholdDate(
      request.products,
      headerStartDate
    );
    if (
      effectiveDate != null &&
      expectedEffectiveDate != null &&
      effectiveDate != expectedEffectiveDate
    ) {
      throw new ChangeConsistencyException(
        '有効日は課金内容が変更された最も古い日付（' +
          EstimateCreateSupport.formatDate(expectedEffectiveDate) +
          '）と一致している必要があります。'
      );
    }

    // 一回課金のみの Change は継続の切替イベント不要（有効日も対象外）
    if (
      !isChangeOneTimeAddOnly(request.products) &&
      !hasChangeBillingEventWithinPreviousTerm(
        request.products,
        previousHistory.CurrentTermStartDate__c,
        previousHistory.CurrentTermEndDate__c
      )
    ) {
      throw new ChangeConsistencyException(
        CHANGE_REQUIRES_BILLING_EVENT_MESSAGE
      );
    }
  }

  private static List<EstimateCreateController.ProductLineItem> toProductLineItemsForChangeValidation(
    List<ContractProduct__c> contractProducts
  ) {
    List<EstimateCreateController.ProductLineItem> lines = new List<EstimateCreateController.ProductLineItem>();
    if (contractProducts == null) {
      return lines;
    }
    for (ContractProduct__c contractProduct : contractProducts) {
      if (contractProduct == null || contractProduct.Product__c == null) {
        continue;
      }
      EstimateCreateController.ProductLineItem line = new EstimateCreateController.ProductLineItem();
      line.contractProductId = contractProduct.Id;
      line.productId = contractProduct.Product__c;
      line.quantity = contractProduct.Quantity__c;
      line.unitPrice = contractProduct.UnitPrice__c;
      line.startDate = EstimateCreateSupport.formatDate(
        contractProduct.StartDate__c
      );
      line.endDate = EstimateCreateSupport.formatDate(
        contractProduct.Enddate__c
      );
      line.invoiceType = contractProduct.InvoiceSetting__c;
      line.billingType = contractProduct.BillingType__c;
      line.recordType = EstimateCreateSupport.normalizeProductRecordType(
        contractProduct.Type__c
      );
      line.typeLabel = line.recordType;
      line.sourceContractProductId = contractProduct.PreviousContractProduct__c;
      lines.add(line);
    }
    return lines;
  }

  private class ProductLineItemStartDateComparator implements Comparator<EstimateCreateController.ProductLineItem> {
    public Integer compare(
      EstimateCreateController.ProductLineItem left,
      EstimateCreateController.ProductLineItem right
    ) {
      if (left == null && right == null) {
        return 0;
      }
      if (left == null) {
        return -1;
      }
      if (right == null) {
        return 1;
      }
      String leftStart = left.startDate == null ? '' : left.startDate;
      String rightStart = right.startDate == null ? '' : right.startDate;
      return leftStart.compareTo(rightStart);
    }
  }

  public static void validateNewSaveRequest(
    EstimateCreateController.EstimateSaveRequest request,
    String contractHistoryName
  ) {
    if (request.opportunityId == null) {
      throw estS1Exception('002', '商談IDが指定されていません。');
    }
    if (String.isBlank(contractHistoryName)) {
      throw estS2NewException('002', '契約履歴名を入力してください。');
    }
    if (String.isBlank(request.contractServiceName)) {
      throw estS2NewException('001', '契約サービス名を入力してください。');
    }

    request.products = filterLinesWithProduct(request.products);
    if (request.products == null || request.products.isEmpty()) {
      throw estS3NewException('009', '商品明細を1行以上入力してください。');
    }

    Boolean hasRecurring = hasActiveRecurringProductLine(request.products);
    if (hasRecurring) {
      if (String.isBlank(request.contractStartDate)) {
        throw estS3NewException(
          '001',
          '期間開始日を入力してください。'
        );
      }
      Date serviceStartDate = EstimateCreateSupport.tryParseDate(
        request.contractStartDate
      );
      if (serviceStartDate == null) {
        throw estS3NewException(
          '002',
          '期間開始日は YYYY-MM-DD 形式で入力してください。'
        );
      }
      if (String.isBlank(request.contractEndDate)) {
        throw estS3NewException(
          '003',
          '期間終了日を入力してください。'
        );
      }
      Date serviceEndDate = EstimateCreateSupport.tryParseDate(
        request.contractEndDate
      );
      if (serviceEndDate == null) {
        throw estS3NewException(
          '004',
          '期間終了日は YYYY-MM-DD 形式で入力してください。'
        );
      }
      if (serviceStartDate > serviceEndDate) {
        throw estS3NewException(
          '005',
          '期間開始日は期間終了日以前の日付を入力してください。'
        );
      }
      if (String.isBlank(request.effectiveDate)) {
        throw estS3NewException(
          '006',
          '切替日を入力してください。'
        );
      }
      Date effectiveDate = EstimateCreateSupport.tryParseDate(
        request.effectiveDate
      );
      if (effectiveDate == null) {
        throw estS3NewException(
          '007',
          '切替日は YYYY-MM-DD 形式で入力してください。'
        );
      }
      if (effectiveDate != serviceStartDate) {
        throw estS3NewException(
          '008',
          '切替日は期間開始日と一致している必要があります。'
        );
      }
    } else {
      // 1回課金のみ（Spot）: 継続課金専用の期間・切替日は持たない
      request.contractStartDate = null;
      request.contractEndDate = null;
      request.effectiveDate = null;
    }

    validateBillingAccount(request);
    validateProductLines(request.products, false, EST_S3_NEW_PREFIX, true);
    validateNewProductLineRules(
      request.products,
      request.contractStartDate,
      request.contractEndDate,
      true,
      EST_S3_NEW_PREFIX
    );
  }

  public static Boolean hasActiveRecurringProductLine(
    List<EstimateCreateController.ProductLineItem> products
  ) {
    if (products == null) {
      return false;
    }
    for (EstimateCreateController.ProductLineItem line : products) {
      if (isActiveProductLine(line) && isRecurringProductLine(line)) {
        return true;
      }
    }
    return false;
  }

  /**
   * Change の課金イベントがすべて一回課金 New 追加のみか。
   * この場合、継続課金の切替日は不要（null）。
   */
  public static Boolean isChangeOneTimeAddOnly(
    List<EstimateCreateController.ProductLineItem> products
  ) {
    List<ChangeBillingEventEntry> entries = collectChangeBillingEventEntries(
      products
    );
    if (entries.isEmpty()) {
      return false;
    }
    for (ChangeBillingEventEntry entry : entries) {
      if (entry == null || entry.isOneTimeOnly != true) {
        return false;
      }
    }
    return true;
  }

  public static List<EstimateCreateController.ProductLineItem> filterLinesWithProduct(
    List<EstimateCreateController.ProductLineItem> products
  ) {
    if (products == null || products.isEmpty()) {
      return products;
    }
    List<EstimateCreateController.ProductLineItem> filtered = new List<EstimateCreateController.ProductLineItem>();
    for (EstimateCreateController.ProductLineItem line : products) {
      if (line != null && line.productId != null) {
        filtered.add(line);
      }
    }
    return filtered;
  }

  /** LWC / テストで getMessage() が実文言になるよう setMessage する */
  public static AuraHandledException wrapAura(String message) {
    String resolved = String.isNotBlank(message)
      ? message
      : '処理中にエラーが発生しました。';
    AuraHandledException ex = new AuraHandledException(resolved);
    ex.setMessage(resolved);
    return ex;
  }

  public static AuraHandledException estS1Exception(
    String code,
    String message
  ) {
    return wrapAura('[EST-S1-' + code + '] ' + message);
  }

  public static AuraHandledException estS2NewException(
    String code,
    String message
  ) {
    return wrapAura('[EST-S2-New-' + code + '] ' + message);
  }

  public static AuraHandledException estSaveException(
    String code,
    String message
  ) {
    return wrapAura('[EST-Save-' + code + '] ' + message);
  }

  public static AuraHandledException estSaveNewException(
    String code,
    String message
  ) {
    return wrapAura('[EST-Save-New-' + code + '] ' + message);
  }

  public static AuraHandledException estS3NewException(
    String code,
    String message
  ) {
    return estS3CodedException(EST_S3_NEW_PREFIX, code, message);
  }

  public static AuraHandledException estS3CodedException(
    String prefix,
    String code,
    String message
  ) {
    if (String.isBlank(prefix)) {
      return wrapAura(message);
    }
    return wrapAura('[' + prefix + '-' + code + '] ' + message);
  }

  public static String estS3NewLineMessage(
    String code,
    Integer rowNumber,
    String body
  ) {
    return estS3CodedLineMessage(EST_S3_NEW_PREFIX, code, rowNumber, body);
  }

  public static String estS3CodedLineMessage(
    String prefix,
    String code,
    Integer rowNumber,
    String body
  ) {
    if (String.isBlank(prefix)) {
      return '商品明細' + rowNumber + '行目: ' + body;
    }
    return '[' +
      prefix +
      '-' +
      code +
      '] 商品明細（' +
      rowNumber +
      '行目）: ' +
      body;
  }

  public static void validateChangeSaveRequest(
    EstimateCreateController.EstimateSaveRequest request,
    String contractHistoryName
  ) {
    validateCommonSaveRequest(request, contractHistoryName, true);

    if (request.contractServiceId == null) {
      throw wrapAura('契約サービスを選択してください。');
    }

    validateContractServiceAccountMatchesOpportunity(request);
    validatePreviousHistory(request);
    assertServiceLifecycle(
      request.contractServiceId,
      ContractDomainConstants.LIFECYCLE_TERM,
      'Change'
    );
    validateChangeEligibility(request.previousHistoryId);
    validateChangePeriodDates(request);
    validateProductLines(request.products, true);
    if (!isChangeOneTimeAddOnly(request.products)) {
      validateChangeEffectiveDateMatchesBillingThreshold(request);
    }
    validateChangeProductLineRules(request);
    validateChangeHasBillingEventInPreviousTerm(request);
  }

  public static void validateChangeEligibility(Id previousHistoryId) {
    ContractHistory__c previousHistory = loadPreviousHistoryTerm(
      previousHistoryId
    );
    if (previousHistory.Type__c == HISTORY_TYPE_CANCEL) {
      throw wrapAura(
        'Churn（解約）済みの契約履歴からChangeは作成できません。'
      );
    }
    // Renew / Cancel と同じ: 期間終了日まで届く継続課金が必須
    if (!EstimateQueryService.isRenewEligibleHistory(previousHistory)) {
      throw wrapAura(
        '前回Versionの期間終了日と一致する継続課金商品がないためChangeできません。'
      );
    }
  }

  public static ContractHistory__c loadPreviousHistoryTerm(
    Id previousHistoryId
  ) {
    List<ContractHistory__c> histories = [
      SELECT Id, Type__c, CurrentTermStartDate__c, CurrentTermEndDate__c
      FROM ContractHistory__c
      WHERE Id = :previousHistoryId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (histories.isEmpty()) {
      throw wrapAura('前回契約履歴が見つかりません。');
    }
    return histories[0];
  }

  public static List<ContractProduct__c> loadChangeSourceProducts(
    Id contractHistoryId
  ) {
    if (contractHistoryId == null) {
      return new List<ContractProduct__c>();
    }

    return [
      SELECT
        Id,
        Product__c,
        Quantity__c,
        UnitPrice__c,
        StartDate__c,
        Enddate__c,
        InvoiceSetting__c
      FROM ContractProduct__c
      WHERE
        ContractHistory__c = :contractHistoryId
        AND (
          BillingType__c = :BILLING_TYPE_RECURRING
          OR (
            BillingType__c = NULL
            AND Product__r.BillingType__c = :BILLING_TYPE_RECURRING
          )
        )
        AND Quantity__c > 0
        AND (Type__c = NULL
        OR Type__c IN (
          :PRODUCT_TYPE_REMAKE,
          :PRODUCT_TYPE_NEW,
          :PRODUCT_TYPE_RENEW
        ))
      WITH SYSTEM_MODE
      ORDER BY Name ASC
    ];
  }

  public static void validateChangePeriodDates(
    EstimateCreateController.EstimateSaveRequest request
  ) {
    ContractHistory__c previousHistory = loadPreviousHistoryTerm(
      request.previousHistoryId
    );
    if (
      previousHistory.CurrentTermStartDate__c == null ||
      previousHistory.CurrentTermEndDate__c == null
    ) {
      throw wrapAura(
        '前回契約履歴の期間開始日または期間終了日が取得できません。'
      );
    }

    Date expectedStartDate = previousHistory.CurrentTermStartDate__c;
    Date previousEndDate = previousHistory.CurrentTermEndDate__c;
    Date headerStartDate = EstimateCreateSupport.parseDate(
      request.contractStartDate
    );
    Date headerEndDate = EstimateCreateSupport.parseDate(
      request.contractEndDate
    );

    if (headerStartDate != expectedStartDate) {
      throw wrapAura(
        '期間開始日は前回Versionの期間開始日と一致している必要があります。'
      );
    }
    if (headerEndDate == null || headerEndDate < previousEndDate) {
      throw wrapAura(
        '期間終了日は前回Versionの期間終了日以降の日付を入力してください。'
      );
    }

    validateNewHeaderMonthlyPeriod(headerStartDate, headerEndDate);
  }

  public static void validateChangeProductLineRules(
    EstimateCreateController.EstimateSaveRequest request
  ) {
    List<ContractProduct__c> sourceProducts = loadChangeSourceProducts(
      request.previousHistoryId
    );
    Map<Id, ContractProduct__c> sourceById = new Map<Id, ContractProduct__c>(
      sourceProducts
    );

    Map<Id, EstimateCreateController.ProductLineItem> originalBySourceId = new Map<Id, EstimateCreateController.ProductLineItem>();
    Map<Id, List<EstimateCreateController.ProductLineItem>> remakesBySourceId = new Map<Id, List<EstimateCreateController.ProductLineItem>>();
    List<EstimateCreateController.ProductLineItem> overlapCandidates = new List<EstimateCreateController.ProductLineItem>();

    Date headerStartDate = EstimateCreateSupport.parseDate(
      request.contractStartDate
    );
    Date headerEndDate = EstimateCreateSupport.parseDate(
      request.contractEndDate
    );

    for (Integer i = 0; i < request.products.size(); i++) {
      EstimateCreateController.ProductLineItem line = request.products[i];
      Integer rowNumber = i + 1;
      line.recordType = EstimateCreateSupport.normalizeProductRecordType(
        line.recordType
      );

      if (EstimateCreateSupport.isChangeOriginalLine(line)) {
        if (line.sourceContractProductId == null) {
          throw wrapAura(
            '商品明細' +
              rowNumber +
              '行目: Original行に元の見積商品が指定されていません。'
          );
        }
        if (originalBySourceId.containsKey(line.sourceContractProductId)) {
          throw wrapAura('Original行が重複しています。');
        }
        ContractProduct__c source = sourceById.get(
          line.sourceContractProductId
        );
        if (source == null) {
          throw wrapAura(
            'Original行は前回Versionの見積商品と一致している必要があります。'
          );
        }
        validateOriginalMatchesSource(line, source, rowNumber);
        originalBySourceId.put(line.sourceContractProductId, line);
        continue;
      }

      if (EstimateCreateSupport.isChangeRemakeLine(line)) {
        if (line.sourceContractProductId == null) {
          throw wrapAura(
            '商品明細' +
              rowNumber +
              '行目: Remake行に元の見積商品が指定されていません。'
          );
        }
        ContractProduct__c remakeSource = sourceById.get(
          line.sourceContractProductId
        );
        if (remakeSource == null) {
          throw wrapAura(
            '商品明細' +
              rowNumber +
              '行目: Remake行の元見積商品が見つかりません。'
          );
        }
        if (line.productId != remakeSource.Product__c) {
          throw wrapAura(
            '商品明細' +
              rowNumber +
              '行目: Remake行の商品はOriginal（前回Version）と同じ商品にしてください。'
          );
        }
        if (!remakesBySourceId.containsKey(line.sourceContractProductId)) {
          remakesBySourceId.put(
            line.sourceContractProductId,
            new List<EstimateCreateController.ProductLineItem>()
          );
        }
        remakesBySourceId.get(line.sourceContractProductId).add(line);
        if (line.productId != null) {
          validateChangeEditableLine(
            line,
            rowNumber,
            headerStartDate,
            headerEndDate
          );
        }
        if (isActiveProductLine(line)) {
          overlapCandidates.add(line);
        }
        continue;
      }

      if (isChangeContinuationLine(line)) {
        if (isActiveProductLine(line)) {
          validateChangeEditableLine(
            line,
            rowNumber,
            headerStartDate,
            headerEndDate
          );
          overlapCandidates.add(line);
        }
        continue;
      }

      if (isActiveProductLine(line)) {
        validateChangeEditableLine(
          line,
          rowNumber,
          headerStartDate,
          headerEndDate
        );
        overlapCandidates.add(line);
      }
    }

    for (ContractProduct__c source : sourceProducts) {
      if (!originalBySourceId.containsKey(source.Id)) {
        throw wrapAura(
          '前回Versionの継続課金商品すべてにOriginal行が必要です。'
        );
      }
      List<EstimateCreateController.ProductLineItem> remakes = remakesBySourceId.get(
        source.Id
      );
      if (remakes == null || remakes.isEmpty()) {
        throw wrapAura(
          '前回Versionの継続課金商品すべてにRemake行を1件以上入力してください。'
        );
      }

      String reconstitutionError = validateChangeReconstitutionCoverage(
        originalBySourceId.get(source.Id),
        remakes
      );
      if (reconstitutionError != null) {
        throw wrapAura(reconstitutionError);
      }
    }

    validateChangeProductPeriodOverlap(overlapCandidates);
    validateChangeRecurringEndEndpointCoverage(
      request.products,
      request.contractEndDate
    );
  }

  public static void validateChangeEffectiveDateMatchesBillingThreshold(
    EstimateCreateController.EstimateSaveRequest request
  ) {
    // 一回課金のみの Change は切替日対象外（送信されても無視）
    if (isChangeOneTimeAddOnly(request.products)) {
      return;
    }
    Date expected = getEarliestChangeBillingThresholdDate(
      request.products,
      EstimateCreateSupport.parseDate(request.contractStartDate)
    );
    if (expected == null) {
      return;
    }
    Date effectiveDate = EstimateCreateSupport.parseDate(request.effectiveDate);
    if (effectiveDate == null) {
      return;
    }
    if (effectiveDate != expected) {
      throw wrapAura(
        '有効日は課金内容が変更された最も古い日付（' +
          EstimateCreateSupport.formatDate(expected) +
          '）と一致している必要があります。'
      );
    }
  }

  public static void validateChangeHasBillingEventInPreviousTerm(
    EstimateCreateController.EstimateSaveRequest request
  ) {
    // 一回課金 New 追加のみは継続の切替イベントではないが、Change として成立させる
    if (isChangeOneTimeAddOnly(request.products)) {
      return;
    }
    ContractHistory__c previousHistory = loadPreviousHistoryTerm(
      request.previousHistoryId
    );
    Date previousStart = previousHistory.CurrentTermStartDate__c;
    Date previousEnd = previousHistory.CurrentTermEndDate__c;
    if (previousStart == null || previousEnd == null) {
      return;
    }
    if (
      !hasChangeBillingEventWithinPreviousTerm(
        request.products,
        previousStart,
        previousEnd
      )
    ) {
      throw wrapAura(CHANGE_REQUIRES_BILLING_EVENT_MESSAGE);
    }
  }

  public static Boolean hasChangeBillingEventWithinPreviousTerm(
    List<EstimateCreateController.ProductLineItem> products,
    Date previousTermStart,
    Date previousTermEnd
  ) {
    if (previousTermStart == null || previousTermEnd == null) {
      return false;
    }
    for (Date eventDate : collectChangeBillingEventDates(products)) {
      if (
        eventDate != null &&
        eventDate >= previousTermStart &&
        eventDate <= previousTermEnd
      ) {
        return true;
      }
    }
    return false;
  }

  public class ChangeBillingEventEntry {
    public Date eventDate;
    public Boolean isOneTimeOnly;

    public ChangeBillingEventEntry(Date eventDate, Boolean isOneTimeOnly) {
      this.eventDate = eventDate;
      this.isOneTimeOnly = isOneTimeOnly == true;
    }
  }

  public static List<Date> collectChangeBillingEventDates(
    List<EstimateCreateController.ProductLineItem> products
  ) {
    List<Date> dates = new List<Date>();
    for (
      ChangeBillingEventEntry entry : collectChangeBillingEventEntries(products)
    ) {
      if (entry != null && entry.eventDate != null) {
        dates.add(entry.eventDate);
      }
    }
    return dates;
  }

  /**
   * Change の課金イベント（日付＋一回課金由来かどうか）。
   * 有効日の請求期間開始日チェック免除判定に使う。
   */
  public static List<ChangeBillingEventEntry> collectChangeBillingEventEntries(
    List<EstimateCreateController.ProductLineItem> products
  ) {
    List<ChangeBillingEventEntry> entries = new List<ChangeBillingEventEntry>();
    Map<Id, EstimateCreateController.ProductLineItem> originalsBySourceId = new Map<Id, EstimateCreateController.ProductLineItem>();
    Map<Id, List<EstimateCreateController.ProductLineItem>> remakesBySourceId = new Map<Id, List<EstimateCreateController.ProductLineItem>>();

    if (products == null) {
      return entries;
    }

    for (EstimateCreateController.ProductLineItem line : products) {
      line.recordType = EstimateCreateSupport.normalizeProductRecordType(
        line.recordType
      );
      if (
        EstimateCreateSupport.isChangeOriginalLine(line) &&
        line.sourceContractProductId != null
      ) {
        originalsBySourceId.put(line.sourceContractProductId, line);
        continue;
      }
      if (
        EstimateCreateSupport.isChangeRemakeLine(line) &&
        line.sourceContractProductId != null
      ) {
        if (!remakesBySourceId.containsKey(line.sourceContractProductId)) {
          remakesBySourceId.put(
            line.sourceContractProductId,
            new List<EstimateCreateController.ProductLineItem>()
          );
        }
        remakesBySourceId.get(line.sourceContractProductId).add(line);
        continue;
      }
      if (
        isChangeContinuationLine(line) &&
        line.productId != null &&
        String.isNotBlank(line.startDate) &&
        line.quantity != null &&
        line.quantity > 0
      ) {
        Date startDate = EstimateCreateSupport.tryParseDate(line.startDate);
        if (startDate != null) {
          entries.add(
            new ChangeBillingEventEntry(
              startDate,
              line.billingType == BILLING_TYPE_ONE_TIME
            )
          );
        }
      }
    }

    for (Id sourceId : originalsBySourceId.keySet()) {
      EstimateCreateController.ProductLineItem original = originalsBySourceId.get(
        sourceId
      );
      List<EstimateCreateController.ProductLineItem> remakes = remakesBySourceId.get(
        sourceId
      );
      if (remakes == null || remakes.isEmpty()) {
        continue;
      }

      List<EstimateCreateController.ProductLineItem> datedRemakes = new List<EstimateCreateController.ProductLineItem>();
      for (EstimateCreateController.ProductLineItem remake : remakes) {
        if (remake != null && String.isNotBlank(remake.startDate)) {
          datedRemakes.add(remake);
        }
      }
      if (datedRemakes.isEmpty()) {
        continue;
      }
      datedRemakes.sort(new ProductLineItemStartDateComparator());

      EstimateCreateController.ProductLineItem first = datedRemakes[0];
      Date originalStart = EstimateCreateSupport.tryParseDate(
        original.startDate
      );
      Date firstStart = EstimateCreateSupport.tryParseDate(first.startDate);
      Boolean pairIsOneTimeOnly =
        original.billingType == BILLING_TYPE_ONE_TIME ||
        first.billingType == BILLING_TYPE_ONE_TIME;
      if (
        originalStart != null &&
        firstStart != null &&
        firstStart > originalStart
      ) {
        // 一回課金系統は切替日計算から除外。
        entries.add(new ChangeBillingEventEntry(firstStart, pairIsOneTimeOnly));
      }

      for (EstimateCreateController.ProductLineItem remake : datedRemakes) {
        Boolean remakeIsOneTimeOnly =
          original.billingType == BILLING_TYPE_ONE_TIME ||
          remake.billingType == BILLING_TYPE_ONE_TIME;
        if (doesChangeBillingContentDiffer(remake, original)) {
          Date remakeStart = EstimateCreateSupport.tryParseDate(
            remake.startDate
          );
          if (remakeStart != null) {
            entries.add(
              new ChangeBillingEventEntry(remakeStart, remakeIsOneTimeOnly)
            );
          }
        }
        // 終了日延長のみ（内容同一）も課金イベント。延長開始日 = Original終了翌日。
        Date originalEnd = EstimateCreateSupport.tryParseDate(original.endDate);
        Date remakeEnd = EstimateCreateSupport.tryParseDate(remake.endDate);
        if (
          originalEnd != null &&
          remakeEnd != null &&
          remakeEnd > originalEnd
        ) {
          entries.add(
            new ChangeBillingEventEntry(
              originalEnd.addDays(1),
              remakeIsOneTimeOnly
            )
          );
        }
      }
    }

    return entries;
  }

  /**
   * 継続課金由来の課金イベントがあるときだけ、有効日を請求期間開始日に縛る。
   * 一回課金 New 追加のみの Change は日割り対象外のため免除する。
   */
  public static Boolean requiresChangeEffectiveDateOnBillingPeriodStart(
    List<EstimateCreateController.ProductLineItem> products
  ) {
    List<ChangeBillingEventEntry> entries = collectChangeBillingEventEntries(
      products
    );
    if (entries.isEmpty()) {
      // イベント未確定時は安全側（従来どおり請求境界を要求）。
      return true;
    }
    for (ChangeBillingEventEntry entry : entries) {
      if (entry == null || entry.isOneTimeOnly != true) {
        return true;
      }
    }
    return false;
  }

  /**
   * 継続課金切替日の基準日（最古）。一回課金イベントは含めない。
   * 継続イベントがなければ null。
   */
  public static Date getEarliestChangeBillingThresholdDate(
    List<EstimateCreateController.ProductLineItem> products,
    Date contractStartDate
  ) {
    List<Date> dates = new List<Date>();
    for (
      ChangeBillingEventEntry entry : collectChangeBillingEventEntries(products)
    ) {
      if (entry != null && entry.eventDate != null && entry.isOneTimeOnly != true) {
        dates.add(entry.eventDate);
      }
    }
    if (dates.isEmpty()) {
      return null;
    }
    dates.sort();
    return dates[0];
  }

  public static Boolean doesChangeBillingContentDiffer(
    EstimateCreateController.ProductLineItem line,
    EstimateCreateController.ProductLineItem original
  ) {
    // ChangeBillingEventUtil と同一判定（SObject アダプタ経由）
    return ChangeBillingEventUtil.doesBillingContentDiffer(
      toContractProductForBillingCompare(line),
      toContractProductForBillingCompare(original)
    );
  }

  private static ContractProduct__c toContractProductForBillingCompare(
    EstimateCreateController.ProductLineItem line
  ) {
    if (line == null) {
      return null;
    }
    return new ContractProduct__c(
      Product__c = line.productId,
      Quantity__c = line.quantity,
      UnitPrice__c = line.unitPrice,
      InvoiceSetting__c = line.invoiceType,
      StartDate__c = EstimateCreateSupport.tryParseDate(line.startDate),
      Enddate__c = EstimateCreateSupport.tryParseDate(line.endDate)
    );
  }

  public static void validateChangeRecurringEndEndpointCoverage(
    List<EstimateCreateController.ProductLineItem> products,
    String headerEndDate
  ) {
    // estimateLineItemUtils.validateChangeRecurringEndEndpointCoverage と定義を揃える:
    // アクティブな継続課金が0件なら終端チェック自体をスキップする。
    Boolean hasActiveRecurring = false;
    Boolean hasRecurringEndMatch = false;

    for (EstimateCreateController.ProductLineItem line : products) {
      if (EstimateCreateSupport.isChangeOriginalLine(line)) {
        continue;
      }
      if (!isActiveProductLine(line) || !isRecurringProductLine(line)) {
        continue;
      }
      hasActiveRecurring = true;
      if (line.endDate == headerEndDate) {
        hasRecurringEndMatch = true;
        break;
      }
    }

    if (!hasActiveRecurring) {
      return;
    }

    if (!hasRecurringEndMatch) {
      throw wrapAura(
        '期間終了日と一致する終了日の継続課金明細が1件以上必要です。'
      );
    }
  }

  public static void validateOriginalMatchesSource(
    EstimateCreateController.ProductLineItem line,
    ContractProduct__c source,
    Integer rowNumber
  ) {
    if (line.productId != source.Product__c) {
      throw wrapAura(
        '商品明細' +
          rowNumber +
          '行目: Original行は前回Versionの見積商品と一致している必要があります。'
      );
    }
    if (!decimalsEqual(line.quantity, source.Quantity__c)) {
      throw wrapAura(
        '商品明細' +
          rowNumber +
          '行目: Original行は前回Versionの見積商品と一致している必要があります。'
      );
    }
    if (!decimalsEqual(line.unitPrice, source.UnitPrice__c)) {
      throw wrapAura(
        '商品明細' +
          rowNumber +
          '行目: Original行は前回Versionの見積商品と一致している必要があります。'
      );
    }
    // estimateLineItemUtils.validateOriginalMatchesSource と同様に normalize 後比較（null/空も揃える）。
    String lineInvoice = ContractMetadataService.normalizeInvoiceSettingLabel(
      line.invoiceType
    );
    String sourceInvoice = ContractMetadataService.normalizeInvoiceSettingLabel(
      source.InvoiceSetting__c
    );
    if (lineInvoice == null) {
      lineInvoice = '';
    }
    if (sourceInvoice == null) {
      sourceInvoice = '';
    }
    if (lineInvoice != sourceInvoice) {
      throw wrapAura(
        '商品明細' +
          rowNumber +
          '行目: Original行は前回Versionの見積商品と一致している必要があります。'
      );
    }
    if (
      EstimateCreateSupport.formatDate(source.StartDate__c) != line.startDate
    ) {
      throw wrapAura(
        '商品明細' +
          rowNumber +
          '行目: Original行は前回Versionの見積商品と一致している必要があります。'
      );
    }
    if (EstimateCreateSupport.formatDate(source.Enddate__c) != line.endDate) {
      throw wrapAura(
        '商品明細' +
          rowNumber +
          '行目: Original行は前回Versionの見積商品と一致している必要があります。'
      );
    }
  }

  public static String validateChangeReconstitutionCoverage(
    EstimateCreateController.ProductLineItem original,
    List<EstimateCreateController.ProductLineItem> derivatives
  ) {
    final String coverageError = CHANGE_REMAKE_COVERAGE_MESSAGE;

    if (original == null || derivatives == null || derivatives.isEmpty()) {
      return '相殺後の商品明細を1行以上入力してください。';
    }

    // Remake のみでカバー判定。「新しい商品」は穴埋めに使わない。
    List<EstimateCreateController.ProductLineItem> segments = buildRemakeReconstitutionSegments(
      derivatives
    );
    if (segments.isEmpty()) {
      return '相殺後の商品明細を1行以上入力してください。';
    }

    // Remake 先頭は Original 開始日と一致必須（遅延開始・前倒し開始ともに不可）。
    if (
      String.isNotBlank(original.startDate) &&
      String.isNotBlank(segments[0].startDate) &&
      segments[0].startDate != original.startDate
    ) {
      if (segments[0].startDate < original.startDate) {
        return 'Remake の開始日は Original 開始日より前にできません。';
      }
      return coverageError;
    }

    for (Integer index = 0; index < segments.size() - 1; index++) {
      Date segmentEnd = EstimateCreateSupport.parseDate(
        segments[index].endDate
      );
      Date nextStart = EstimateCreateSupport.parseDate(
        segments[index + 1].startDate
      );
      if (segmentEnd == null || nextStart == null) {
        return coverageError;
      }
      // 隣接必須（終了日の翌日 = 次の開始日）。重複・隙間の両方を弾く。
      if (nextStart != segmentEnd.addDays(1)) {
        return coverageError;
      }
    }

    EstimateCreateController.ProductLineItem lastSegment = segments[
      segments.size() - 1
    ];
    Date originalEnd = EstimateCreateSupport.parseDate(original.endDate);
    Date lastEnd = EstimateCreateSupport.parseDate(lastSegment.endDate);
    // Original終了日までカバーすること。終了日の延長（lastEnd > originalEnd）は許容。
    if (originalEnd != null && (lastEnd == null || lastEnd < originalEnd)) {
      return coverageError;
    }

    return null;
  }

  public static List<EstimateCreateController.ProductLineItem> buildRemakeReconstitutionSegments(
    List<EstimateCreateController.ProductLineItem> derivatives
  ) {
    List<EstimateCreateController.ProductLineItem> segments = new List<EstimateCreateController.ProductLineItem>();
    if (derivatives != null) {
      for (EstimateCreateController.ProductLineItem derivative : derivatives) {
        if (isReconstitutionSegment(derivative)) {
          segments.add(derivative);
        }
      }
    }
    segments.sort(new ProductLineItemStartDateComparator());
    return segments;
  }

  public static Boolean isReconstitutionSegment(
    EstimateCreateController.ProductLineItem line
  ) {
    return line != null &&
      line.productId != null &&
      String.isNotBlank(line.startDate) &&
      String.isNotBlank(line.endDate) &&
      line.quantity != null &&
      line.quantity > 0;
  }

  public static List<EstimateCreateController.ProductLineItem> normalizeChangeProductsForSave(
    List<EstimateCreateController.ProductLineItem> products
  ) {
    if (products == null || products.isEmpty()) {
      return products == null
        ? new List<EstimateCreateController.ProductLineItem>()
        : products;
    }

    List<EstimateCreateController.ProductLineItem> normalized = new List<EstimateCreateController.ProductLineItem>();
    for (EstimateCreateController.ProductLineItem line : products) {
      if (line == null || line.productId == null) {
        continue;
      }
      line.recordType = EstimateCreateSupport.normalizeProductRecordType(
        line.recordType
      );
      if (
        String.isBlank(line.typeLabel) && String.isNotBlank(line.recordType)
      ) {
        line.typeLabel = line.recordType;
      }
      normalized.add(line);
    }
    return normalized;
  }

  public static Boolean isChangeContinuationLine(
    EstimateCreateController.ProductLineItem line
  ) {
    if (
      line == null ||
      EstimateCreateSupport.isChangeOriginalLine(line) ||
      EstimateCreateSupport.isChangeRemakeLine(line)
    ) {
      return false;
    }
    String recordType = EstimateCreateSupport.normalizeProductRecordType(
      line.recordType
    );
    if (
      recordType == PRODUCT_TYPE_NEW &&
      line.sourceContractProductId == null
    ) {
      return true;
    }
    if (
      recordType == PRODUCT_TYPE_REMAKE &&
      line.sourceContractProductId == null
    ) {
      return true;
    }
    return false;
  }

  public static void validateChangeEditableLine(
    EstimateCreateController.ProductLineItem line,
    Integer rowNumber,
    Date headerStartDate,
    Date headerEndDate
  ) {
    if (String.isBlank(line.startDate) || String.isBlank(line.endDate)) {
      throw wrapAura(
        '商品明細' + rowNumber + '行目: 開始日と終了日を入力してください。'
      );
    }

    Date lineStartDate = EstimateCreateSupport.parseDate(line.startDate);
    Date lineEndDate = EstimateCreateSupport.parseDate(line.endDate);
    if (
      lineStartDate != null &&
      lineEndDate != null &&
      lineStartDate > lineEndDate
    ) {
      throw wrapAura(
        '商品明細' +
          rowNumber +
          '行目: 開始日は終了日以前の日付を入力してください。'
      );
    }
    // 継続課金のみヘッダ（継続課金の契約期間）内制約。一回課金は非連動。
    if (isRecurringProductLine(line)) {
      if (
        lineStartDate != null &&
        headerStartDate != null &&
        lineStartDate < headerStartDate
      ) {
        throw wrapAura(
          '商品明細' +
            rowNumber +
            '行目: 開始日は期間開始日以降の日付を入力してください。'
        );
      }
      if (
        lineEndDate != null &&
        headerEndDate != null &&
        lineEndDate > headerEndDate
      ) {
        throw wrapAura(
          '商品明細' +
            rowNumber +
            '行目: 終了日は期間終了日以前の日付を入力してください。'
        );
      }
    }

    String billingTypeError = validateBillingTypeRequired(
      line,
      rowNumber,
      null
    );
    if (billingTypeError != null) {
      throw wrapAura(billingTypeError);
    }

    if (String.isBlank(line.invoiceType)) {
      throw wrapAura(
        '商品明細' + rowNumber + '行目: 請求設定を選択してください。'
      );
    }
    String invoiceSettingError = validateInvoiceSettingLine(line, rowNumber);
    if (invoiceSettingError != null) {
      throw wrapAura(invoiceSettingError);
    }
  }

  public static void validateChangeProductPeriodOverlap(
    List<EstimateCreateController.ProductLineItem> products
  ) {
    validateNewProductPeriodOverlap(products);
  }

  public static Boolean decimalsEqual(Decimal left, Decimal right) {
    if (left == null && right == null) {
      return true;
    }
    if (left == null || right == null) {
      return false;
    }
    return left.stripTrailingZeros().equals(right.stripTrailingZeros());
  }

  public static void validateRenewSaveRequest(
    EstimateCreateController.EstimateSaveRequest request,
    String contractHistoryName
  ) {
    validateCommonSaveRequest(request, contractHistoryName, true);

    if (request.contractServiceId == null) {
      throw wrapAura('契約サービスを選択してください。');
    }

    validateContractServiceAccountMatchesOpportunity(request);
    validatePreviousHistory(request);
    assertServiceLifecycle(
      request.contractServiceId,
      ContractDomainConstants.LIFECYCLE_TERM,
      'Renew'
    );
    validateRenewEligibility(request.previousHistoryId);
    validateRenewPeriodStartDate(request);
    validateProductLines(request.products, false, EST_S3_RENEW_PREFIX);
    validateRenewProductLineRules(
      request.products,
      request.contractStartDate,
      request.contractEndDate
    );
  }

  public static void validateRenewEligibility(Id previousHistoryId) {
    validateRecurringSourceEligibility(previousHistoryId, 'Renew');
  }

  public static void validateCancelEligibility(Id previousHistoryId) {
    validateRecurringSourceEligibility(previousHistoryId, 'Cancel');
  }

  public static void validateRecurringSourceEligibility(
    Id previousHistoryId,
    String targetOperation
  ) {
    List<ContractHistory__c> histories = [
      SELECT Id, Type__c, CurrentTermEndDate__c
      FROM ContractHistory__c
      WHERE Id = :previousHistoryId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (histories.isEmpty()) {
      throw wrapAura('前回契約履歴が見つかりません。');
    }

    ContractHistory__c history = histories[0];
    if (history.Type__c == HISTORY_TYPE_CANCEL) {
      if (targetOperation == 'Renew') {
        throw wrapAura(
          'Churn（解約）済みの契約履歴からRenewは作成できません。'
        );
      }
      throw wrapAura(
        'Churn（解約）済みの契約履歴からCancelは作成できません。'
      );
    }
    if (
      history.CurrentTermEndDate__c == null ||
      EstimateQueryService.countRenewSourceRecurringProducts(
        history.Id,
        history.CurrentTermEndDate__c
      ) == 0
    ) {
      if (targetOperation == 'Renew') {
        throw estS3CodedException(
          EST_S3_RENEW_PREFIX,
          '029',
          '前回Versionの期間終了日と一致する継続課金商品がないためRenewできません。'
        );
      }
      throw wrapAura(
        '前回Versionの期間終了日と一致する継続課金商品がないためCancelできません。'
      );
    }
  }

  public static void validateRenewPeriodStartDate(
    EstimateCreateController.EstimateSaveRequest request
  ) {
    List<ContractHistory__c> histories = [
      SELECT CurrentTermEndDate__c
      FROM ContractHistory__c
      WHERE Id = :request.previousHistoryId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (histories.isEmpty() || histories[0].CurrentTermEndDate__c == null) {
      throw wrapAura(
        '前回契約履歴の期間終了日が取得できません。'
      );
    }

    Date expectedStartDate = histories[0].CurrentTermEndDate__c.addDays(1);
    Date serviceStartDate = EstimateCreateSupport.parseDate(
      request.contractStartDate
    );
    if (serviceStartDate != expectedStartDate) {
      throw estS3CodedException(
        EST_S3_RENEW_PREFIX,
        '028',
        '期間開始日は前回Versionの期間終了日の翌日である必要があります。'
      );
    }
  }

  public static void validateRenewProductLineRules(
    List<EstimateCreateController.ProductLineItem> products,
    String headerStartDate,
    String headerEndDate
  ) {
    if (products == null || products.isEmpty()) {
      return;
    }

    Boolean hasActiveLine = false;
    Boolean hasRecurringLine = false;
    for (Integer i = 0; i < products.size(); i++) {
      EstimateCreateController.ProductLineItem line = products[i];
      if (!isActiveProductLine(line)) {
        continue;
      }
      hasActiveLine = true;
      if (isRecurringProductLine(line)) {
        hasRecurringLine = true;
      }
    }

    if (!hasActiveLine) {
      throw estS3CodedException(
        EST_S3_RENEW_PREFIX,
        '009',
        '商品明細を1行以上入力してください。'
      );
    }
    if (!hasRecurringLine) {
      throw estS3CodedException(
        EST_S3_RENEW_PREFIX,
        '027',
        'Renewでは継続課金商品を1行以上指定してください。一回課金のみのRenewはできません。'
      );
    }

    validateNewProductLineRules(
      products,
      headerStartDate,
      headerEndDate,
      true,
      EST_S3_RENEW_PREFIX
    );
  }

  public static void validateAddSaveRequest(
    EstimateCreateController.EstimateSaveRequest request,
    String contractHistoryName
  ) {
    if (request.opportunityId == null) {
      throw wrapAura('商談IDが指定されていません。');
    }
    if (String.isBlank(contractHistoryName)) {
      throw wrapAura('契約履歴名を入力してください。');
    }
    if (request.contractServiceId == null) {
      throw wrapAura('契約サービスを選択してください。');
    }

    validateContractServiceAccountMatchesOpportunity(request);
    validatePreviousHistory(request);

    List<ContractService__c> services = [
      SELECT Id, Lifecycle__c
      FROM ContractService__c
      WHERE Id = :request.contractServiceId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (services.isEmpty()) {
      throw wrapAura('契約サービスが見つかりません。');
    }
    assertLoadedLifecycle(
      services[0].Lifecycle__c,
      ContractDomainConstants.LIFECYCLE_SPOT,
      'Add'
    );

    request.products = filterLinesWithProduct(request.products);
    if (request.products == null || request.products.isEmpty()) {
      throw wrapAura('商品明細を1行以上入力してください。');
    }
    for (Integer i = 0; i < request.products.size(); i++) {
      EstimateCreateController.ProductLineItem line = request.products[i];
      if (!isActiveProductLine(line)) {
        continue;
      }
      if (isRecurringProductLine(line)) {
        throw wrapAura(
          '商品明細' +
            (i + 1) +
            '行目: Add では一回課金商品のみ指定できます。'
        );
      }
    }

    validateProductLines(request.products, false);
    // Add: 継続課金専用の期間・切替日は持たない
    request.contractStartDate = null;
    request.contractEndDate = null;
    request.effectiveDate = null;
  }

  public static void assertServiceLifecycle(
    Id contractServiceId,
    String expectedLifecycle,
    String operationLabel
  ) {
    if (contractServiceId == null) {
      throw wrapAura('契約サービスを選択してください。');
    }
    List<ContractService__c> services = [
      SELECT Id, Lifecycle__c
      FROM ContractService__c
      WHERE Id = :contractServiceId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (services.isEmpty()) {
      throw wrapAura('契約サービスが見つかりません。');
    }
    assertLoadedLifecycle(
      services[0].Lifecycle__c,
      expectedLifecycle,
      operationLabel
    );
  }

  public static void assertLoadedLifecycle(
    String lifecycle,
    String expectedLifecycle,
    String operationLabel
  ) {
    if (String.isBlank(lifecycle)) {
      throw wrapAura(LIFECYCLE_UNASSIGNED_MESSAGE);
    }
    if (lifecycle == expectedLifecycle) {
      return;
    }
    if (expectedLifecycle == ContractDomainConstants.LIFECYCLE_SPOT) {
      throw wrapAura(
        'Add は都度契約（Spot）の契約サービスのみ選択できます。期間契約への1回課金追加は Change を使ってください。'
      );
    }
    throw wrapAura(
      '都度契約では ' +
        operationLabel +
        ' は使えません。Add を選んでください。'
    );
  }

  public static void validateCancelSaveRequest(
    EstimateCreateController.EstimateSaveRequest request,
    String contractHistoryName
  ) {
    validateCommonSaveRequest(request, contractHistoryName, false);

    if (request.contractServiceId == null) {
      throw wrapAura('契約サービスを選択してください。');
    }

    validateContractServiceAccountMatchesOpportunity(request);
    validatePreviousHistory(request);
    assertServiceLifecycle(
      request.contractServiceId,
      ContractDomainConstants.LIFECYCLE_TERM,
      'Cancel'
    );
    validateCancelEligibility(request.previousHistoryId);
    validateCancelPeriodDates(request);
    validateCancelNoProducts(request.products);

    if (
      String.isBlank(request.contractStartDate) ||
      String.isBlank(request.contractEndDate)
    ) {
      throw wrapAura('解約日が取得できません。');
    }

    if (request.contractStartDate != request.contractEndDate) {
      throw wrapAura('解約日の開始日と終了日が一致しません。');
    }
  }

  public static void validateCancelPeriodDates(
    EstimateCreateController.EstimateSaveRequest request
  ) {
    List<ContractHistory__c> histories = [
      SELECT CurrentTermEndDate__c
      FROM ContractHistory__c
      WHERE Id = :request.previousHistoryId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (histories.isEmpty() || histories[0].CurrentTermEndDate__c == null) {
      throw wrapAura(
        '前回契約履歴の期間終了日が取得できません。'
      );
    }

    Date expectedCancelDate = histories[0].CurrentTermEndDate__c.addDays(1);
    Date cancelStartDate = EstimateCreateSupport.parseDate(
      request.contractStartDate
    );
    Date cancelEndDate = EstimateCreateSupport.parseDate(
      request.contractEndDate
    );
    if (
      cancelStartDate != expectedCancelDate ||
      cancelEndDate != expectedCancelDate
    ) {
      throw wrapAura(
        '解約日は前回Versionの期間終了日の翌日である必要があります。'
      );
    }
  }

  public static void validateCancelNoProducts(
    List<EstimateCreateController.ProductLineItem> products
  ) {
    if (products == null || products.isEmpty()) {
      return;
    }

    for (EstimateCreateController.ProductLineItem line : products) {
      if (isActiveProductLine(line)) {
        throw wrapAura('Cancelでは商品明細を入力できません。');
      }
    }
  }

  public static void validateBillingAccount(
    EstimateCreateController.EstimateSaveRequest request
  ) {
    if (request.billingAccountId == null) {
      return;
    }

    List<BillingAccount__c> billingAccounts = [
      SELECT Id
      FROM BillingAccount__c
      WHERE Id = :request.billingAccountId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (billingAccounts.isEmpty()) {
      throw estSaveNewException('002', '請求アカウントが見つかりません。');
    }
  }

  /**
   * Change/Renew/Cancel 保存時、契約サービスの取引先と商談の取引先が一致していることを確認する。
   * InvoiceProductGenerationService.validateContractServiceAndOpportunityAccounts と同じ趣旨。
   */
  public static void validateContractServiceAccountMatchesOpportunity(
    EstimateCreateController.EstimateSaveRequest request
  ) {
    if (request.contractServiceId == null || request.opportunityId == null) {
      return;
    }
    List<ContractService__c> services = [
      SELECT Id, Account__c
      FROM ContractService__c
      WHERE Id = :request.contractServiceId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (services.isEmpty()) {
      return;
    }
    List<Opportunity> opportunities = [
      SELECT Id, AccountId
      FROM Opportunity
      WHERE Id = :request.opportunityId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (opportunities.isEmpty()) {
      return;
    }
    Id serviceAccountId = services[0].Account__c;
    Id opportunityAccountId = opportunities[0].AccountId;
    if (serviceAccountId == null || opportunityAccountId == null) {
      return;
    }
    if (serviceAccountId == opportunityAccountId) {
      return;
    }
    throw wrapAura(
      '契約サービスの取引先と商談の取引先が一致しません' +
        '（契約サービス取引先: ' +
        String.valueOf(serviceAccountId) +
        ' / 商談取引先: ' +
        String.valueOf(opportunityAccountId) +
        '）。'
    );
  }

  public static void validatePreviousHistory(
    EstimateCreateController.EstimateSaveRequest request
  ) {
    if (request.previousHistoryId == null) {
      throw wrapAura('前回契約履歴が指定されていません。');
    }

    List<ContractHistory__c> histories = [
      SELECT Id, ContractService__c
      FROM ContractHistory__c
      WHERE Id = :request.previousHistoryId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (histories.isEmpty()) {
      throw wrapAura('前回契約履歴が見つかりません。');
    }
    if (histories[0].ContractService__c != request.contractServiceId) {
      throw wrapAura(
        '前回契約履歴が契約サービスと一致しません。'
      );
    }

    // 正: サービスの最新 Ordered（New/Change/Renew。Cancel は除外）
    ContractHistory__c latest = EstimateQueryService.queryLatestActiveOrderedHistory(
      request.contractServiceId
    );
    if (latest == null) {
      throw wrapAura(
        '前回契約履歴（最新の受注）が見つかりません。'
      );
    }
    if (latest.Id != request.previousHistoryId) {
      throw wrapAura(
        '前回契約履歴は最新の受注（Ordered）を指定してください。画面を開き直してください。'
      );
    }
  }

  public static void validateCommonSaveRequest(
    EstimateCreateController.EstimateSaveRequest request,
    String contractHistoryName,
    Boolean requireProducts
  ) {
    if (request.opportunityId == null) {
      throw wrapAura('商談IDが指定されていません。');
    }

    if (String.isBlank(contractHistoryName)) {
      throw wrapAura('契約履歴名を入力してください。');
    }

    if (
      String.isBlank(request.contractStartDate) ||
      String.isBlank(request.contractEndDate)
    ) {
      throw wrapAura(
        '期間開始日と期間終了日を入力してください。'
      );
    }

    Date serviceStartDate = EstimateCreateSupport.parseDate(
      request.contractStartDate
    );
    Date serviceEndDate = EstimateCreateSupport.parseDate(
      request.contractEndDate
    );
    if (
      serviceStartDate != null &&
      serviceEndDate != null &&
      serviceStartDate > serviceEndDate
    ) {
      throw wrapAura(
        '期間開始日は期間終了日以前の日付を入力してください。'
      );
    }

    validateHistoryMetaDates(request, serviceStartDate, serviceEndDate);

    if (
      requireProducts &&
      (request.products == null || request.products.isEmpty())
    ) {
      throw wrapAura('商品明細を1行以上入力してください。');
    }
  }

  public static void validateHistoryMetaDates(
    EstimateCreateController.EstimateSaveRequest request,
    Date serviceStartDate,
    Date serviceEndDate
  ) {
    if (
      request.selectedType == HISTORY_TYPE_CHANGE &&
      isChangeOneTimeAddOnly(request.products)
    ) {
      request.effectiveDate = null;
      return;
    }

    if (request.selectedType == HISTORY_TYPE_ADD) {
      request.effectiveDate = null;
      return;
    }
    // New で明細があり継続ゼロのときだけ切替日不要（明細未設定の単体検証は従来どおり）
    if (
      request.selectedType == HISTORY_TYPE_NEW &&
      request.products != null &&
      !hasActiveRecurringProductLine(request.products)
    ) {
      request.effectiveDate = null;
      return;
    }

    if (String.isBlank(request.effectiveDate)) {
      throw wrapAura('切替日を入力してください。');
    }
    Date effectiveDate = EstimateCreateSupport.parseDate(request.effectiveDate);
    if (effectiveDate == null) {
      throw wrapAura(
        '切替日の形式が正しくありません。'
      );
    }

    if (request.selectedType == 'Change') {
      if (request.previousHistoryId == null) {
        throw wrapAura('前回契約履歴が指定されていません。');
      }
      ContractHistory__c previousHistory = loadPreviousHistoryTerm(
        request.previousHistoryId
      );
      if (
        previousHistory.CurrentTermStartDate__c == null ||
        previousHistory.CurrentTermEndDate__c == null
      ) {
        throw wrapAura(
          '前回契約履歴の期間開始日または期間終了日が取得できません。'
        );
      }
      Date previousStartDate = previousHistory.CurrentTermStartDate__c;
      Date previousEndDate = previousHistory.CurrentTermEndDate__c;
      if (effectiveDate < previousStartDate) {
        throw wrapAura(
          '切替日は前回Versionの契約開始日から契約終了日の間で入力してください。'
        );
      }
      if (effectiveDate > previousEndDate) {
        throw wrapAura(
          '切替日が前回Versionの契約終了日を超えているため、ChangeではなくRenewで作成してください。'
        );
      }
      if (
        requiresChangeEffectiveDateOnBillingPeriodStart(request.products) &&
        !MonthlyBillingPeriodUtil.isMonthlyPeriodStartDate(
          previousStartDate,
          effectiveDate
        )
      ) {
        throw wrapAura(CHANGE_EFFECTIVE_DATE_BILLING_PERIOD_START_MESSAGE);
      }
      return;
    }

    if (request.selectedType == 'New') {
      if (serviceStartDate != null && effectiveDate != serviceStartDate) {
        throw estS3NewException(
          '008',
          '切替日は期間開始日と一致している必要があります。'
        );
      }
      return;
    }

    if (request.selectedType == 'Renew' || request.selectedType == 'Cancel') {
      if (request.previousHistoryId == null) {
        throw wrapAura('前回契約履歴が指定されていません。');
      }
      List<ContractHistory__c> previousHistories = [
        SELECT CurrentTermEndDate__c
        FROM ContractHistory__c
        WHERE Id = :request.previousHistoryId
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      if (
        previousHistories.isEmpty() ||
        previousHistories[0].CurrentTermEndDate__c == null
      ) {
        throw wrapAura(
          '前回契約履歴の期間終了日が取得できません。'
        );
      }
      Date expectedEffective = previousHistories[0]
        .CurrentTermEndDate__c.addDays(1);
      if (effectiveDate != expectedEffective) {
        throw estS3CodedException(
          EST_S3_RENEW_PREFIX,
          '031',
          '切替日は前回契約履歴の契約終了日の翌日である必要があります。'
        );
      }
    }
  }

  public static void validateProductLines(
    List<EstimateCreateController.ProductLineItem> products,
    Boolean isChangeType
  ) {
    validateProductLines(products, isChangeType, null);
  }

  public static void validateProductLines(
    List<EstimateCreateController.ProductLineItem> products,
    Boolean isChangeType,
    String s3ErrorPrefix
  ) {
    validateProductLines(products, isChangeType, s3ErrorPrefix, false);
  }

  public static void validateProductLines(
    List<EstimateCreateController.ProductLineItem> products,
    Boolean isChangeType,
    String s3ErrorPrefix,
    Boolean allowRecurringToOneTimeOverride
  ) {
    Map<Id, Product2> productById = EstimateSaveService.loadProductBillingTypes(
      products
    );
    for (Integer i = 0; i < products.size(); i++) {
      EstimateCreateController.ProductLineItem line = products[i];
      Integer rowNumber = i + 1;

      // 商品未選択の下書き行はスキップ（LWC isBlankProductLine と揃える）
      if (line.productId == null) {
        continue;
      }

      Product2 productMaster = productById.get(line.productId);
      if (
        productMaster == null ||
        productMaster.AvailableForContract__c != true
      ) {
        throw wrapAura(
          estS3CodedLineMessage(
            s3ErrorPrefix,
            '026',
            rowNumber,
            '契約管理で利用可能な商品のみ選択できます。'
          )
        );
      }

      String billingTypeError = validateBillingTypeRequired(
        line,
        rowNumber,
        s3ErrorPrefix
      );
      if (billingTypeError != null) {
        throw wrapAura(billingTypeError);
      }

      // 原則はマスタ一致。New のみ継続→一回の上書きを許可。
      if (
        String.isNotBlank(line.billingType) &&
        line.billingType != productMaster.BillingType__c
      ) {
        Boolean allowedDowngrade =
          allowRecurringToOneTimeOverride == true &&
          ContractMetadataService.isRecurringBillingType(
            productMaster.BillingType__c
          ) &&
          line.billingType == BILLING_TYPE_ONE_TIME;
        if (!allowedDowngrade) {
          throw wrapAura(
            estS3CodedLineMessage(
              s3ErrorPrefix,
              '032',
              rowNumber,
              '課金種別が商品マスタと一致しません。'
            )
          );
        }
      }

      Boolean isOriginalLine =
        isChangeType && EstimateCreateSupport.isChangeOriginalLine(line);

      // Remake も数量1以上必須（途中終了は数量維持＋単価0）。Original のみ数量0許容。
      if (!isOriginalLine) {
        if (line.quantity == null || line.quantity <= 0) {
          throw wrapAura(
            estS3CodedLineMessage(
              s3ErrorPrefix,
              '016',
              rowNumber,
              '数量を入力してください。'
            )
          );
        }
      }

      // 単価は必須（明示的な0は許容、未入力のみエラー）。Original は前回条件の打消しのため対象外。
      if (!isOriginalLine && line.unitPrice == null) {
        throw wrapAura(
          estS3CodedLineMessage(
            s3ErrorPrefix,
            '033',
            rowNumber,
            '単価を入力してください。'
          )
        );
      }

      String periodError = validateBillingPeriod(
        line,
        rowNumber,
        s3ErrorPrefix
      );
      if (periodError != null) {
        throw wrapAura(periodError);
      }

      String invoiceSettingError = validateInvoiceSettingLine(
        line,
        rowNumber,
        s3ErrorPrefix
      );
      if (invoiceSettingError != null) {
        throw wrapAura(invoiceSettingError);
      }

      // 数量が0でないアクティブ行で金額が計算できていない場合は保存させない（LWC側と同じ判定）。
      if (line.amount == null && line.quantity != null && line.quantity != 0) {
        throw wrapAura(
          estS3CodedLineMessage(
            s3ErrorPrefix,
            '034',
            rowNumber,
            '金額を計算できません。期間を確認してください。'
          )
        );
      }
    }
  }

  public static String validateInvoiceSettingLine(
    EstimateCreateController.ProductLineItem line,
    Integer rowNumber
  ) {
    return validateInvoiceSettingLine(line, rowNumber, null);
  }

  public static String validateInvoiceSettingLine(
    EstimateCreateController.ProductLineItem line,
    Integer rowNumber,
    String s3ErrorPrefix
  ) {
    if (String.isBlank(line.invoiceType)) {
      return null;
    }
    if (String.isBlank(line.billingType)) {
      return estS3CodedLineMessage(
        s3ErrorPrefix,
        '027',
        rowNumber,
        '課金種別を指定してください。'
      );
    }
    String billingType = line.billingType;
    String validationError = ContractMetadataService.validateInvoiceSettingForBillingType(
      billingType,
      line.invoiceType
    );
    if (validationError == null) {
      return null;
    }
    String code = '023';
    if (validationError.contains('一回課金')) {
      code = '021';
    } else if (validationError.contains('継続課金')) {
      code = '022';
    }
    return estS3CodedLineMessage(
      s3ErrorPrefix,
      code,
      rowNumber,
      validationError
    );
  }

  public static String validateBillingTypeRequired(
    EstimateCreateController.ProductLineItem line,
    Integer rowNumber,
    String s3ErrorPrefix
  ) {
    if (String.isBlank(line.billingType)) {
      return estS3CodedLineMessage(
        s3ErrorPrefix,
        '027',
        rowNumber,
        '課金種別を指定してください。'
      );
    }
    if (
      line.billingType != BILLING_TYPE_RECURRING &&
      line.billingType != BILLING_TYPE_ONE_TIME
    ) {
      return estS3CodedLineMessage(
        s3ErrorPrefix,
        '027',
        rowNumber,
        '課金種別は継続課金または一回課金を指定してください。'
      );
    }
    return null;
  }

  public static void validateNewProductLineRules(
    List<EstimateCreateController.ProductLineItem> products,
    String headerStartDate,
    String headerEndDate,
    Boolean includeProductOverlap
  ) {
    validateNewProductLineRules(
      products,
      headerStartDate,
      headerEndDate,
      includeProductOverlap,
      null
    );
  }

  public static void validateNewProductLineRules(
    List<EstimateCreateController.ProductLineItem> products,
    String headerStartDate,
    String headerEndDate,
    Boolean includeProductOverlap,
    String s3ErrorPrefix
  ) {
    Date headerStart = EstimateCreateSupport.parseDate(headerStartDate);
    Date headerEnd = EstimateCreateSupport.parseDate(headerEndDate);
    Boolean hasRecurringLine = false;

    for (Integer i = 0; i < products.size(); i++) {
      EstimateCreateController.ProductLineItem line = products[i];
      Integer rowNumber = i + 1;

      if (line.productId == null) {
        continue;
      }

      if (String.isBlank(line.startDate) || String.isBlank(line.endDate)) {
        throw wrapAura(
          estS3CodedLineMessage(
            s3ErrorPrefix,
            '015',
            rowNumber,
            '開始日と終了日を入力してください。'
          )
        );
      }

      Date lineStart = EstimateCreateSupport.parseDate(line.startDate);
      Date lineEnd = EstimateCreateSupport.parseDate(line.endDate);

      if (lineStart != null && lineEnd != null && lineStart > lineEnd) {
        throw wrapAura(
          estS3CodedLineMessage(
            s3ErrorPrefix,
            '017',
            rowNumber,
            '開始日は終了日以前の日付を入力してください。'
          )
        );
      }

      // 継続課金のみヘッダ内制約。一回課金は継続課金の契約期間と非連動。
      if (isRecurringProductLine(line)) {
        if (
          lineStart != null &&
          headerStart != null &&
          lineStart < headerStart
        ) {
          throw wrapAura(
            estS3CodedLineMessage(
              s3ErrorPrefix,
              '018',
              rowNumber,
              '開始日は期間開始日以降の日付を入力してください。'
            )
          );
        }

        if (lineEnd != null && headerEnd != null && lineEnd > headerEnd) {
          throw wrapAura(
            estS3CodedLineMessage(
              s3ErrorPrefix,
              '019',
              rowNumber,
              '終了日は期間終了日以前の日付を入力してください。'
            )
          );
        }
      }

      if (isActiveProductLine(line) && String.isBlank(line.invoiceType)) {
        throw wrapAura(
          estS3CodedLineMessage(
            s3ErrorPrefix,
            '020',
            rowNumber,
            '請求設定を選択してください。'
          )
        );
      }

      if (isActiveProductLine(line) && String.isNotBlank(line.invoiceType)) {
        String invoiceSettingError = validateInvoiceSettingLine(
          line,
          rowNumber,
          s3ErrorPrefix
        );
        if (invoiceSettingError != null) {
          throw wrapAura(invoiceSettingError);
        }
      }

      if (isActiveProductLine(line) && isRecurringProductLine(line)) {
        hasRecurringLine = true;
      }
    }

    if (hasRecurringLine) {
      validateNewHeaderMonthlyPeriod(headerStart, headerEnd, s3ErrorPrefix);
      validateNewRecurringEndpointCoverage(
        products,
        headerStartDate,
        headerEndDate,
        s3ErrorPrefix
      );
    }

    if (includeProductOverlap == true) {
      validateNewProductPeriodOverlap(products, s3ErrorPrefix);
    }
  }

  public static Boolean isActiveProductLine(
    EstimateCreateController.ProductLineItem line
  ) {
    return line.productId != null && line.quantity != null && line.quantity > 0;
  }

  public static Boolean isRecurringProductLine(
    EstimateCreateController.ProductLineItem line
  ) {
    // LWC isRecurringLine と同様、billingType が継続課金のときのみ継続扱い
    return line.billingType == BILLING_TYPE_RECURRING;
  }

  public static void validateNewHeaderMonthlyPeriod(
    Date headerStart,
    Date headerEnd
  ) {
    validateNewHeaderMonthlyPeriod(headerStart, headerEnd, null);
  }

  public static void validateNewHeaderMonthlyPeriod(
    Date headerStart,
    Date headerEnd,
    String s3ErrorPrefix
  ) {
    if (headerStart == null || headerEnd == null) {
      return;
    }
    Integer cycles = ContractMetadataService.countMonthlyBillingCycles(
      headerStart,
      headerEnd
    );
    if (cycles == null || cycles < 1) {
      throw estS3CodedException(
        s3ErrorPrefix,
        '010',
        '期間開始日と期間終了日はヘッダー期間開始日起点の月次分割である必要があります（カレンダー月分割は使えません）。'
      );
    }
  }

  public static void validateNewRecurringEndpointCoverage(
    List<EstimateCreateController.ProductLineItem> products,
    String headerStartDate,
    String headerEndDate
  ) {
    validateNewRecurringEndpointCoverage(
      products,
      headerStartDate,
      headerEndDate,
      null
    );
  }

  public static void validateNewRecurringEndpointCoverage(
    List<EstimateCreateController.ProductLineItem> products,
    String headerStartDate,
    String headerEndDate,
    String s3ErrorPrefix
  ) {
    Boolean hasRecurringStartMatch = false;
    Boolean hasRecurringEndMatch = false;

    for (EstimateCreateController.ProductLineItem line : products) {
      if (!isActiveProductLine(line) || !isRecurringProductLine(line)) {
        continue;
      }
      if (line.startDate == headerStartDate) {
        hasRecurringStartMatch = true;
      }
      if (line.endDate == headerEndDate) {
        hasRecurringEndMatch = true;
      }
    }

    if (!hasRecurringStartMatch) {
      throw estS3CodedException(
        s3ErrorPrefix,
        '011',
        '期間開始日と一致する開始日の継続課金明細が1件以上必要です。'
      );
    }
    if (!hasRecurringEndMatch) {
      throw estS3CodedException(
        s3ErrorPrefix,
        '012',
        '期間終了日と一致する終了日の継続課金明細が1件以上必要です。'
      );
    }
  }

  public static void validateNewProductPeriodOverlap(
    List<EstimateCreateController.ProductLineItem> products
  ) {
    validateNewProductPeriodOverlap(products, null);
  }

  public static void validateNewProductPeriodOverlap(
    List<EstimateCreateController.ProductLineItem> products,
    String s3ErrorPrefix
  ) {
    // estimateLineItemUtils の期間重複チェックと同定義:
    // 継続・一回を問わずアクティブ行の同一商品期間重複を弾く。
    List<EstimateCreateController.ProductLineItem> activeLines = new List<EstimateCreateController.ProductLineItem>();
    for (EstimateCreateController.ProductLineItem line : products) {
      if (isActiveProductLine(line)) {
        activeLines.add(line);
      }
    }

    for (Integer i = 0; i < activeLines.size(); i++) {
      EstimateCreateController.ProductLineItem left = activeLines[i];
      Date leftStart = EstimateCreateSupport.parseDate(left.startDate);
      Date leftEnd = EstimateCreateSupport.parseDate(left.endDate);
      if (leftStart == null || leftEnd == null) {
        continue;
      }

      for (Integer j = i + 1; j < activeLines.size(); j++) {
        EstimateCreateController.ProductLineItem right = activeLines[j];
        if (left.productId != right.productId) {
          continue;
        }

        Date rightStart = EstimateCreateSupport.parseDate(right.startDate);
        Date rightEnd = EstimateCreateSupport.parseDate(right.endDate);
        if (rightStart == null || rightEnd == null) {
          continue;
        }

        if (leftStart <= rightEnd && leftEnd >= rightStart) {
          throw estS3CodedException(
            s3ErrorPrefix,
            '013',
            '同一商品の契約期間が重複しています。商品ごとに期間が重ならないよう入力してください。'
          );
        }
      }
    }
  }

  public static String validateBillingPeriod(
    EstimateCreateController.ProductLineItem line,
    Integer rowNumber
  ) {
    return validateBillingPeriod(line, rowNumber, null);
  }

  public static String validateBillingPeriod(
    EstimateCreateController.ProductLineItem line,
    Integer rowNumber,
    String s3ErrorPrefix
  ) {
    if (line.billingType != BILLING_TYPE_RECURRING) {
      return null;
    }
    if (String.isBlank(line.startDate) || String.isBlank(line.endDate)) {
      return estS3CodedLineMessage(
        s3ErrorPrefix,
        '015',
        rowNumber,
        '開始日と終了日を入力してください。'
      );
    }
    // 終了日を正規化して通さない（LWC validateBillingPeriod と同じ厳密判定）。
    Date startDate = EstimateCreateSupport.parseDate(line.startDate);
    Date endDate = EstimateCreateSupport.parseDate(line.endDate);
    Integer cycles = ContractMetadataService.countMonthlyBillingCycles(
      startDate,
      endDate
    );
    if (cycles == null || cycles < 1) {
      return estS3CodedLineMessage(
        s3ErrorPrefix,
        '024',
        rowNumber,
        '開始日・終了日は明細開始日起点の月次分割である必要があります（カレンダー月分割は使えません）。'
      );
    }
    return null;
  }

  public static void validateWizardCustomFields(
    EstimateCreateController.EstimateSaveRequest request
  ) {
    validateWizardCustomFields(request, false);
  }

  public static void validateWizardCustomFields(
    EstimateCreateController.EstimateSaveRequest request,
    Boolean includeReadonlyProductLines
  ) {
    if (request == null) {
      return;
    }

    // 表示中かつ Required の契約サービス／履歴カスタムは種別問わず必須（Cancel 含む）。
    // 備考 UI のみ Cancel で出さない。商品明細は Cancel 0件のため下の products ループは実質スキップ。
    String serviceError = ContractWizardFieldService.validateRequiredCustomFields(
      ContractWizardFieldService.WizardTarget.ContractService,
      request.contractServiceCustomFields,
      null,
      request.selectedType
    );
    if (String.isNotBlank(serviceError)) {
      throw wrapAura(serviceError);
    }
    String serviceTypeError = ContractWizardFieldService.validateCustomFieldTypes(
      ContractWizardFieldService.WizardTarget.ContractService,
      request.contractServiceCustomFields,
      null,
      request.selectedType
    );
    if (String.isNotBlank(serviceTypeError)) {
      throw wrapAura(serviceTypeError);
    }
    String historyError = ContractWizardFieldService.validateRequiredCustomFields(
      ContractWizardFieldService.WizardTarget.ContractHistory,
      request.contractHistoryCustomFields,
      null,
      request.selectedType
    );
    if (String.isNotBlank(historyError)) {
      throw wrapAura(historyError);
    }
    String historyTypeError = ContractWizardFieldService.validateCustomFieldTypes(
      ContractWizardFieldService.WizardTarget.ContractHistory,
      request.contractHistoryCustomFields,
      null,
      request.selectedType
    );
    if (String.isNotBlank(historyTypeError)) {
      throw wrapAura(historyTypeError);
    }
    if (request.products == null) {
      return;
    }
    Map<Id, Product2> productById = EstimateSaveService.loadProductBillingTypes(
      request.products
    );
    for (EstimateCreateController.ProductLineItem line : request.products) {
      if (line == null || line.productId == null) {
        continue;
      }
      if (includeReadonlyProductLines != true && line.isReadonly == true) {
        continue;
      }
      // Change の Original はウィザード追加項目の対象外（必須検証もしない）
      if (EstimateCreateSupport.isChangeOriginalLine(line)) {
        continue;
      }
      // 保存判定の正は常に Product2。クライアントの productVisibilityContext は使わない。
      Map<String, String> visibilityContext = ContractWizardFieldService.buildProductVisibilityContext(
        productById.get(line.productId)
      );
      String productError = ContractWizardFieldService.validateRequiredCustomFields(
        ContractWizardFieldService.WizardTarget.ContractProduct,
        line.customFields,
        visibilityContext,
        request.selectedType
      );
      if (String.isNotBlank(productError)) {
        throw wrapAura(productError);
      }
      String productTypeError = ContractWizardFieldService.validateCustomFieldTypes(
        ContractWizardFieldService.WizardTarget.ContractProduct,
        line.customFields,
        visibilityContext,
        request.selectedType
      );
      if (String.isNotBlank(productTypeError)) {
        throw wrapAura(productTypeError);
      }
    }
  }
}
