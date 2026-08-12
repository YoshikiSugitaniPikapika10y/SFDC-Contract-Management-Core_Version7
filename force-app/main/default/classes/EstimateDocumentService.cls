/**
 * 見積書の表示データ組み立て・PDF 発行・ファイル保存。
 *
 * 導入先ブランド表記は下記定数を差し替える（値変更はそのまま PDF に反映される）。
 * プライバシーポリシー URL は Visualforce `EstimateDocumentPdf` 側も合わせて確認する。
 */
public without sharing class EstimateDocumentService {
  // --- 導入先ブランド（見積書ヘッダ／フッタ）。導入時に差し替え ---
  public static final String COMPANY_NAME = 'テスト株式会社';
  public static final String COMPANY_POSTAL_CODE = '100 - 0001';
  public static final String COMPANY_ADDRESS_LINE1 = '東京都千代田区テスト1-1-1';
  public static final String COMPANY_ADDRESS_LINE2 = 'テストビル 1階';
  public static final String COMPANY_REGISTRATION_NUMBER = 'T0000000000000';

  @TestVisible
  private static final String ESTIMATE_STATUS_REQUIRED_MESSAGE = '見積書の表示・発行はステータスが Estimate の契約履歴のみ利用できます。';

  public class LineDto {
    public String productName;
    public Decimal quantity;
    public String unit;
    public Decimal unitPrice;
    public Decimal amount;
    public String periodLabel;
    public String billingType;
    public String invoiceSetting;
    public String typeLabel;
  }

  /** 商談 EstimatePdf と同じ明細行 DTO */
  public class GroupedLineDto {
    public String breakdown;
    public String unit;
    public Decimal quantity;
    public Decimal amount;
    public String period;
  }

  /** 商談 EstimatePdf と同じ商品名グループ DTO */
  public class GroupDto {
    public String productName;
    public List<GroupedLineDto> items;
    public Decimal groupTotal;
    public Decimal taxAmount;
    public Decimal totalAmountIncTax;

    public GroupDto(String name) {
      productName = String.isBlank(name) ? '' : name;
      items = new List<GroupedLineDto>();
      groupTotal = 0;
      taxAmount = 0;
      totalAmountIncTax = 0;
    }
  }

  public class DocumentContext {
    public ContractHistory__c history;
    public List<LineDto> lines;
    public Decimal lineTotal;
    public Decimal taxPercent;
    public Decimal taxAmount;
    public Decimal lineTotalInclTax;
    public String taxPercentLabel;
    public String companyName;
    public String companyPostalCode;
    public String companyAddressLine1;
    public String companyAddressLine2;
    public String companyRegistrationNumber;
    public String addresseeName;
    public String accountName;
    public String masterNoteText;
    public String documentTitle;
    public String estimateDateLabel;
    public String validDateLabel;
    public String issueDateLabel;
    public String termLabel;
    public String typeLabel;
    // 商談 EstimatePdf 互換の表示値
    public EstimateSetting__c estimateSetting;
    public String toCompanyNameDisplay;
    public String ownerNameDisplay;
    public String estimateDateDisplay;
    public String termFeeStartDateDisplay;
    public String estimateNumber;
    public List<GroupDto> digitalGroups;
    public List<GroupDto> consultingGroups;
    public List<GroupDto> trainingGroups;
    public List<GroupDto> otherGroups;
    public Decimal digitalTotalIncTax;
    public Decimal consultingTotalIncTax;
    public Decimal trainingTotalIncTax;
    public Decimal otherTotalIncTax;
    public Decimal totalAmount;
  }

  public class IssueResult {
    public Id contentVersionId;
    public String fileName;
    public Date issueDate;
  }

  public class EstimateDocumentException extends Exception {
  }

  public static DocumentContext loadContext(Id contractHistoryId) {
    if (contractHistoryId == null) {
      throw new EstimateDocumentException('契約履歴IDが指定されていません。');
    }

    List<ContractHistory__c> histories = [
      SELECT
        Id,
        Name,
        Type__c,
        historystatus__c,
        EstimateTitleName__c,
        EstimateDate__c,
        EstimateValidDate__c,
        EstimateIssueDate__c,
        Note__c,
        CurrentTermStartDate__c,
        CurrentTermEndDate__c,
        DeltaAmountSum__c,
        EstimateNoteMaster__r.NoteText__c,
        Opportunity__c,
        Opportunity__r.Name,
        Opportunity__r.Owner.Name,
        ContractService__r.TaxPercent__c,
        ContractService__r.Account__r.Name,
        ContractService__r.BiilingAcccount__r.BillingAddressee__c
      FROM ContractHistory__c
      WHERE Id = :contractHistoryId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (histories.isEmpty()) {
      throw new EstimateDocumentException('契約履歴が見つかりません。');
    }
    assertEstimateStatusForDocument(histories[0]);

    DocumentContext context = new DocumentContext();
    context.history = histories[0];
    context.companyName = COMPANY_NAME;
    context.companyPostalCode = COMPANY_POSTAL_CODE;
    context.companyAddressLine1 = COMPANY_ADDRESS_LINE1;
    context.companyAddressLine2 = COMPANY_ADDRESS_LINE2;
    context.companyRegistrationNumber = COMPANY_REGISTRATION_NUMBER;
    context.lines = loadLines(contractHistoryId, context.history.Type__c);
    context.lineTotal = resolveLineTotal(context.history, context.lines);
    // Percent 項目の Apex 値（0.1＝10%）を表示％へ戻してから正規化する。未入力は 0%。
    context.taxPercent = TaxCalculationUtil.resolveTaxPercent(
      TaxCalculationUtil.fromPercentFieldStorage(
        context.history.ContractService__r == null
          ? null
          : context.history.ContractService__r.TaxPercent__c
      )
    );
    context.taxAmount = TaxCalculationUtil.calculateTaxAmount(
      context.lineTotal,
      context.taxPercent
    );
    context.lineTotalInclTax = TaxCalculationUtil.calculateAmountInclTax(
      context.lineTotal,
      context.taxPercent
    );
    context.taxPercentLabel = TaxCalculationUtil.formatTaxPercentLabel(
      context.taxPercent
    );
    context.addresseeName = resolveAddresseeName(context.history);
    context.accountName = resolveAccountName(context.history);
    context.masterNoteText = context.history.EstimateNoteMaster__r == null
      ? null
      : context.history.EstimateNoteMaster__r.NoteText__c;
    context.documentTitle = resolveDocumentTitle(context.history);
    context.estimateDateLabel = formatDisplayDate(
      context.history.EstimateDate__c
    );
    context.validDateLabel = formatDisplayDate(
      context.history.EstimateValidDate__c
    );
    context.issueDateLabel = formatDisplayDate(
      context.history.EstimateIssueDate__c
    );
    context.termLabel = buildTermLabel(
      context.history.CurrentTermStartDate__c,
      context.history.CurrentTermEndDate__c
    );
    context.typeLabel = resolveHistoryTypeLabel(context.history.Type__c);
    buildGroupedPdfContext(context);
    return context;
  }

  /**
   * 見積書 PDF は Estimate のみ。Ordered／Archive は Dynamic Actions 非表示に加え、
   * URL 直叩きでも Apex で拒否する。
   */
  @TestVisible
  private static void assertEstimateStatusForDocument(
    ContractHistory__c history
  ) {
    if (
      history == null ||
      history.historystatus__c !=
      ContractDomainConstants.HISTORY_STATUS_ESTIMATE
    ) {
      throw new EstimateDocumentException(ESTIMATE_STATUS_REQUIRED_MESSAGE);
    }
  }

  public static IssueResult issueEstimateDocument(Id contractHistoryId) {
    DocumentContext context = loadContext(contractHistoryId);
    Date issueDate = ensureIssueDate(context.history);
    context.history.EstimateIssueDate__c = issueDate;
    context.issueDateLabel = formatDisplayDate(issueDate);

    String fileName = buildFileName(context.history, issueDate);
    Blob pdfBody = generatePdfBlob(contractHistoryId);
    Id contentVersionId = savePdfToRecord(contractHistoryId, fileName, pdfBody);

    IssueResult result = new IssueResult();
    result.contentVersionId = contentVersionId;
    result.fileName = fileName;
    result.issueDate = issueDate;
    return result;
  }

  /**
   * 発行日は自動で本日をセットしない。未設定なら null のまま返す（ユーザーが明示的に入力するまで確定させない）。
   */
  public static Date ensureIssueDate(ContractHistory__c history) {
    if (history == null || history.Id == null) {
      throw new EstimateDocumentException('契約履歴が指定されていません。');
    }
    return history.EstimateIssueDate__c;
  }

  public static String buildFileName(
    ContractHistory__c history,
    Date issueDate
  ) {
    String title = resolveDocumentTitle(history);
    String sanitizedTitle = sanitizeFileName(title);
    Date targetIssueDate = issueDate == null ? Date.today() : issueDate;
    return sanitizedTitle + '_' + formatFileDate(targetIssueDate) + '.pdf';
  }

  public static Id savePdfToRecord(Id recordId, String fileName, Blob pdfBody) {
    if (recordId == null) {
      throw new EstimateDocumentException(
        '保存先の契約履歴IDが指定されていません。'
      );
    }
    if (pdfBody == null || pdfBody.size() == 0) {
      throw new EstimateDocumentException('PDFデータが空です。');
    }

    String normalizedFileName = String.isBlank(fileName)
      ? 'estimate.pdf'
      : fileName;
    String title = normalizedFileName.endsWith('.pdf')
      ? normalizedFileName.substring(0, normalizedFileName.length() - 4)
      : normalizedFileName;

    ContentVersion contentVersion = new ContentVersion(
      Title = title,
      PathOnClient = normalizedFileName,
      VersionData = pdfBody
    );
    SystemContextAccess.insertRecords(new List<SObject>{ contentVersion });

    Id contentDocumentId = [
      SELECT ContentDocumentId
      FROM ContentVersion
      WHERE Id = :contentVersion.Id
      WITH SYSTEM_MODE
      LIMIT 1
    ]
    .ContentDocumentId;

    ContentDocumentLink documentLink = new ContentDocumentLink(
      ContentDocumentId = contentDocumentId,
      LinkedEntityId = recordId,
      ShareType = 'V',
      Visibility = 'AllUsers'
    );
    SystemContextAccess.insertRecords(new List<SObject>{ documentLink });
    return contentVersion.Id;
  }

  public static Blob generatePdfBlob(Id contractHistoryId) {
    if (Test.isRunningTest()) {
      return Blob.valueOf('%PDF-1.4 test');
    }

    PageReference pdfPage = Page.EstimateDocumentPdf;
    pdfPage.getParameters().put('id', contractHistoryId);
    return pdfPage.getContentAsPDF();
  }

  private static List<LineDto> loadLines(
    Id contractHistoryId,
    String historyType
  ) {
    List<ContractProduct__c> products = [
      SELECT
        Id,
        Product__c,
        Product__r.Name,
        Product__r.UnitName__c,
        Product__r.BillingType__c,
        Unit__c,
        UnitPrice__c,
        Quantity__c,
        StartDate__c,
        Enddate__c,
        InvoiceSetting__c,
        BillingType__c,
        Type__c,
        Amount__c,
        PreviousContractProduct__c
      FROM ContractProduct__c
      WHERE ContractHistory__c = :contractHistoryId
      WITH SYSTEM_MODE
      ORDER BY Name ASC
    ];
    products = ChangeBillingEventUtil.filterProductsForEstimateDocument(
      historyType,
      products
    );

    List<LineDto> lines = new List<LineDto>();
    for (ContractProduct__c product : products) {
      LineDto line = new LineDto();
      line.billingType = String.isNotBlank(product.BillingType__c)
        ? product.BillingType__c
        : product.Product__r == null ? '' : product.Product__r.BillingType__c;
      line.productName = product.Product__r == null
        ? ''
        : product.Product__r.Name;
      line.quantity = product.Quantity__c == null
        ? 0
        : product.Quantity__c.setScale(2, RoundingMode.HALF_UP);
      line.unitPrice = product.UnitPrice__c == null
        ? 0
        : product.UnitPrice__c.setScale(2, RoundingMode.HALF_UP);
      line.amount = resolveLineAmount(product, line.billingType);
      line.invoiceSetting = ContractMetadataService.normalizeInvoiceSettingLabel(
        product.InvoiceSetting__c
      );
      line.unit = String.isNotBlank(product.Unit__c)
        ? product.Unit__c
        : buildDisplayUnit(
            product.Product__r == null ? null : product.Product__r.UnitName__c,
            line.billingType
          );
      line.periodLabel = buildPeriodLabel(
        product.StartDate__c,
        product.Enddate__c
      );
      line.typeLabel = resolveProductTypeLabel(product.Type__c);
      lines.add(line);
    }
    return lines;
  }

  private static Decimal resolveLineAmount(
    ContractProduct__c product,
    String billingType
  ) {
    if (product.Amount__c != null) {
      return product.Amount__c;
    }
    Decimal calculatedAmount = ContractProductAmountUtil.calculateSignedAmount(
      product,
      billingType
    );
    return calculatedAmount == null ? 0 : calculatedAmount;
  }

  private static Decimal resolveLineTotal(
    ContractHistory__c history,
    List<LineDto> lines
  ) {
    if (history != null && history.DeltaAmountSum__c != null) {
      return history.DeltaAmountSum__c;
    }
    return sumLineAmounts(lines);
  }

  private static Decimal sumLineAmounts(List<LineDto> lines) {
    Decimal total = 0;
    if (lines == null) {
      return total;
    }
    for (LineDto line : lines) {
      total += line.amount == null ? 0 : line.amount;
    }
    return total;
  }

  private static String resolveDocumentTitle(ContractHistory__c history) {
    if (history == null) {
      return '見積書';
    }
    if (String.isNotBlank(history.EstimateTitleName__c)) {
      return history.EstimateTitleName__c.trim();
    }
    if (
      history.Opportunity__r != null &&
      String.isNotBlank(history.Opportunity__r.Name)
    ) {
      return history.Opportunity__r.Name.trim();
    }
    if (String.isNotBlank(history.Name)) {
      return history.Name.trim();
    }
    return '見積書';
  }

  private static String resolveAddresseeName(ContractHistory__c history) {
    if (
      history.ContractService__r != null &&
      history.ContractService__r.BiilingAcccount__r != null &&
      String.isNotBlank(
        history.ContractService__r.BiilingAcccount__r.BillingAddressee__c
      )
    ) {
      return history.ContractService__r.BiilingAcccount__r.BillingAddressee__c;
    }
    return resolveAccountName(history);
  }

  private static String resolveAccountName(ContractHistory__c history) {
    if (
      history != null &&
      history.ContractService__r != null &&
      history.ContractService__r.Account__r != null &&
      String.isNotBlank(history.ContractService__r.Account__r.Name)
    ) {
      return history.ContractService__r.Account__r.Name;
    }
    return '';
  }

  private static String resolveHistoryTypeLabel(String historyType) {
    if (historyType == 'New') {
      return '新規';
    }
    if (historyType == 'Change') {
      return '変更';
    }
    if (historyType == 'Renew') {
      return '更新';
    }
    if (historyType == 'Cancel') {
      return '解約';
    }
    return historyType;
  }

  private static String resolveProductTypeLabel(String productType) {
    if (productType == 'New') {
      return '新規';
    }
    if (productType == 'Renew') {
      return '更新';
    }
    if (productType == 'Original') {
      return '変更前';
    }
    if (productType == 'Remake' || productType == 'derivative') {
      return '変更後';
    }
    return productType;
  }

  private static String buildDisplayUnit(String unitName, String billingType) {
    // マスタ単位をそのまま表示する（継続課金でも「・月」は付与しない）。
    if (String.isBlank(unitName)) {
      return '式';
    }
    return unitName;
  }

  private static String buildPeriodLabel(Date startDate, Date endDate) {
    if (startDate == null && endDate == null) {
      return '';
    }
    if (startDate != null && endDate != null) {
      return formatDisplayDate(startDate) + ' 〜 ' + formatDisplayDate(endDate);
    }
    if (startDate != null) {
      return formatDisplayDate(startDate) + ' 〜';
    }
    return '〜 ' + formatDisplayDate(endDate);
  }

  private static String buildTermLabel(Date startDate, Date endDate) {
    return buildPeriodLabel(startDate, endDate);
  }

  public static String formatDisplayDate(Date value) {
    if (value == null) {
      return '';
    }
    return String.valueOf(value.year()) +
      '年' +
      String.valueOf(value.month()).leftPad(2, '0') +
      '月' +
      String.valueOf(value.day()).leftPad(2, '0') +
      '日';
  }

  public static String formatFileDate(Date value) {
    Date targetDate = value == null ? Date.today() : value;
    return String.valueOf(targetDate.year()) +
      '_' +
      String.valueOf(targetDate.month()).leftPad(2, '0') +
      '_' +
      String.valueOf(targetDate.day()).leftPad(2, '0');
  }

  public static String sanitizeFileName(String value) {
    if (String.isBlank(value)) {
      return '見積書';
    }
    String sanitized = value.trim();
    sanitized = sanitized.replaceAll('[\\\\/:*?"<>|]', '_');
    sanitized = sanitized.replaceAll('\\s+', '_');
    return String.isBlank(sanitized) ? '見積書' : sanitized;
  }

  /**
   * カテゴリ別グループを組み立て、税込を付与する。
   * 税の正はウィザード／請求ヘッダと同じく「PDF 掲載明細の税抜合計 × 税率を1回切り捨て」。
   * グループ／カテゴリ税込は、その総額税を税抜比で按分した表示（最後のグループで端数吸収）。
   */
  @TestVisible
  private static void buildGroupedPdfContext(DocumentContext context) {
    context.estimateSetting = loadEstimateSetting(context.history);
    context.estimateNumber = generateEstimateNumber(context.history);
    buildDisplayValues(context);

    context.digitalGroups = new List<GroupDto>();
    context.consultingGroups = new List<GroupDto>();
    context.trainingGroups = new List<GroupDto>();
    context.otherGroups = new List<GroupDto>();
    context.digitalTotalIncTax = 0;
    context.consultingTotalIncTax = 0;
    context.trainingTotalIncTax = 0;
    context.otherTotalIncTax = 0;
    context.totalAmount = 0;

    List<ContractProduct__c> products = queryProductsForGroupedPdf(
      context.history.Id,
      context.history.Type__c
    );

    for (ContractProduct__c product : products) {
      GroupedLineDto item = toGroupedLine(product);
      String category = product.Product__r == null ? null : product.Product__r.Field1__c;
      String groupingName = resolveGroupingProductName(product);

      if (category == '研修（エンパワー）') {
        addToGroup(context.trainingGroups, groupingName, item);
      } else if (category != null && category.left(4) == 'SaaS') {
        addToGroup(context.digitalGroups, groupingName, item);
      } else if (category == 'コンサル') {
        addToGroup(context.consultingGroups, groupingName, item);
      } else {
        addToGroup(context.otherGroups, groupingName, item);
      }
    }

    List<GroupDto> allGroups = new List<GroupDto>();
    allGroups.addAll(context.digitalGroups);
    allGroups.addAll(context.consultingGroups);
    allGroups.addAll(context.trainingGroups);
    allGroups.addAll(context.otherGroups);

    Decimal grandExcl = sumGroupExcl(allGroups);
    Decimal grandTax = TaxCalculationUtil.calculateTaxAmount(
      grandExcl,
      context.taxPercent
    );
    allocateGrandTaxToGroups(allGroups, grandExcl, grandTax);

    context.digitalTotalIncTax = sumGroupTotalIncTax(context.digitalGroups);
    context.consultingTotalIncTax = sumGroupTotalIncTax(context.consultingGroups);
    context.trainingTotalIncTax = sumGroupTotalIncTax(context.trainingGroups);
    context.otherTotalIncTax = sumGroupTotalIncTax(context.otherGroups);
    context.totalAmount = grandExcl + grandTax;
    // PDF 御見積と loadContext 側の税込正本を揃える（掲載明細ベース）。
    context.lineTotal = grandExcl;
    context.taxAmount = grandTax;
    context.lineTotalInclTax = context.totalAmount;
  }

  private static Decimal sumGroupExcl(List<GroupDto> groups) {
    Decimal total = 0;
    if (groups == null) {
      return total;
    }
    for (GroupDto groupDto : groups) {
      if (groupDto != null && groupDto.groupTotal != null) {
        total += groupDto.groupTotal;
      }
    }
    return total;
  }

  private static Decimal sumGroupTotalIncTax(List<GroupDto> groups) {
    Decimal total = 0;
    if (groups == null) {
      return total;
    }
    for (GroupDto groupDto : groups) {
      if (groupDto != null && groupDto.totalAmountIncTax != null) {
        total += groupDto.totalAmountIncTax;
      }
    }
    return total;
  }

  /**
   * 総額税をグループ税抜比で按分。最後のグループで端数を吸収し、
   * グループ税込の合計＝御見積金額になるようにする。
   */
  private static void allocateGrandTaxToGroups(
    List<GroupDto> groups,
    Decimal grandExcl,
    Decimal grandTax
  ) {
    if (groups == null || groups.isEmpty()) {
      return;
    }
    Decimal taxTotal = grandTax == null ? 0 : grandTax;
    Decimal exclTotal = grandExcl == null ? 0 : grandExcl;
    if (exclTotal == 0 || taxTotal == 0) {
      for (GroupDto groupDto : groups) {
        if (groupDto == null) {
          continue;
        }
        groupDto.taxAmount = 0;
        groupDto.totalAmountIncTax = groupDto.groupTotal == null
          ? 0
          : groupDto.groupTotal;
      }
      return;
    }

    Decimal remainingTax = taxTotal;
    for (Integer i = 0; i < groups.size(); i++) {
      GroupDto groupDto = groups[i];
      if (groupDto == null) {
        continue;
      }
      Decimal groupExcl = groupDto.groupTotal == null ? 0 : groupDto.groupTotal;
      Decimal groupTax;
      if (i == groups.size() - 1) {
        groupTax = remainingTax;
      } else {
        groupTax = (taxTotal * groupExcl / exclTotal)
          .setScale(0, RoundingMode.HALF_UP);
        remainingTax -= groupTax;
      }
      groupDto.taxAmount = groupTax;
      groupDto.totalAmountIncTax = groupExcl + groupTax;
    }
  }

  private static List<ContractProduct__c> queryProductsForGroupedPdf(
    Id contractHistoryId,
    String historyType
  ) {
    List<ContractProduct__c> products = [
      SELECT
        Id,
        Product__c,
        Product__r.Name,
        Product__r.Field1__c,
        Product__r.UnitName__c,
        Product__r.BillingType__c,
        Description__c,
        Unit__c,
        UnitPrice__c,
        Quantity__c,
        StartDate__c,
        Enddate__c,
        InvoiceSetting__c,
        BillingType__c,
        Type__c,
        Amount__c,
        PreviousContractProduct__c
      FROM ContractProduct__c
      WHERE ContractHistory__c = :contractHistoryId
      WITH SYSTEM_MODE
      ORDER BY StartDate__c ASC NULLS LAST, Name ASC
    ];
    return ChangeBillingEventUtil.filterProductsForEstimateDocument(
      historyType,
      products
    );
  }

  private static GroupedLineDto toGroupedLine(ContractProduct__c product) {
    String billingType = String.isNotBlank(product.BillingType__c)
      ? product.BillingType__c
      : product.Product__r == null ? '' : product.Product__r.BillingType__c;

    GroupedLineDto item = new GroupedLineDto();
    item.breakdown = String.isNotBlank(product.Description__c)
      ? product.Description__c
      : product.Product__r == null ? '' : product.Product__r.Name;
    item.unit = String.isNotBlank(product.Unit__c)
      ? product.Unit__c
      : buildDisplayUnit(
          product.Product__r == null ? null : product.Product__r.UnitName__c,
          billingType
        );
    item.quantity = product.Quantity__c == null
      ? 0
      : product.Quantity__c.setScale(2, RoundingMode.HALF_UP);
    item.amount = resolveLineAmount(product, billingType);
    item.period = buildPeriodLabel(product.StartDate__c, product.Enddate__c);
    return item;
  }

  private static String resolveGroupingProductName(ContractProduct__c product) {
    if (product.Product__r != null && String.isNotBlank(product.Product__r.Name)) {
      return product.Product__r.Name;
    }
    return itemFallbackName(product);
  }

  private static String itemFallbackName(ContractProduct__c product) {
    return String.isNotBlank(product.Description__c)
      ? product.Description__c
      : '';
  }

  private static void addToGroup(
    List<GroupDto> targetList,
    String productName,
    GroupedLineDto item
  ) {
    GroupDto foundGroup = null;
    for (GroupDto existingGroup : targetList) {
      if (existingGroup.productName == productName) {
        foundGroup = existingGroup;
        break;
      }
    }
    if (foundGroup == null) {
      foundGroup = new GroupDto(productName);
      targetList.add(foundGroup);
    }
    foundGroup.items.add(item);
    if (item.amount != null) {
      foundGroup.groupTotal += item.amount;
    }
  }

  private static EstimateSetting__c loadEstimateSetting(
    ContractHistory__c history
  ) {
    if (history == null || history.Opportunity__c == null) {
      return buildFallbackEstimateSetting(history);
    }

    List<EstimateSetting__c> settings = [
      SELECT
        Id,
        Opportunity__c,
        ToCompanyName__c,
        EstimateTitle__c,
        OtherFeeLavel__c,
        Tax__c,
        TermFeeStartDate__c,
        TermFeeStartDateSencence__c,
        EstimateDateLabel__c,
        EstimateDateSentence__c,
        OwnerLabel__c,
        OwnerName__c,
        PostalNumber__c,
        AdressFirstHalf__c,
        AddressLastHalf__c,
        CompanyName__c,
        TELLabel__c,
        TELValue__c,
        FAXLabel__c,
        FAXSentence__c,
        PaymentTerm__c,
        PaymentTermSentence__c,
        TermDueDate__c,
        EstimateDueDateSentence__c,
        BasicTermPeriodLabel__c,
        BasicTermPeriod__c,
        EstimateSumLabel__c,
        UnitLabel__c,
        UnitSentence__c,
        HonorificTitle__c,
        DigitalLicenceFeeLabel__c,
        ConsultingFeeLabel__c,
        FeedbackCoacingFeeLabel__c,
        NoteSentenceLabel__c,
        NoteSencente__c,
        EstimateNumberLabel__c,
        EstimateSentence__c
      FROM EstimateSetting__c
      WHERE Opportunity__c = :history.Opportunity__c
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (settings.isEmpty()) {
      return buildFallbackEstimateSetting(history);
    }
    return settings[0];
  }

  @TestVisible
  private static EstimateSetting__c buildFallbackEstimateSetting(
    ContractHistory__c history
  ) {
    EstimateSetting__c fallback = new EstimateSetting__c();
    fallback.EstimateTitle__c = resolveDocumentTitle(history);
    fallback.ToCompanyName__c = resolveAddresseeName(history);
    fallback.CompanyName__c = COMPANY_NAME;
    fallback.PostalNumber__c = COMPANY_POSTAL_CODE;
    fallback.AdressFirstHalf__c = COMPANY_ADDRESS_LINE1;
    fallback.AddressLastHalf__c = COMPANY_ADDRESS_LINE2;
    fallback.HonorificTitle__c = '御中';
    fallback.EstimateSentence__c = '下記の通り、お見積り申し上げます。';
    fallback.BasicTermPeriodLabel__c = '基本契約期間';
    fallback.BasicTermPeriod__c = buildTermLabel(
      history == null ? null : history.CurrentTermStartDate__c,
      history == null ? null : history.CurrentTermEndDate__c
    );
    fallback.PaymentTerm__c = '支払条件';
    fallback.PaymentTermSentence__c = '';
    fallback.TermFeeStartDate__c = '取引料金開始日';
    fallback.TermDueDate__c = '見積有効期限';
    fallback.EstimateDueDateSentence__c = history == null
      ? ''
      : formatDisplayDate(history.EstimateValidDate__c);
    fallback.EstimateSumLabel__c = '御見積金額';
    fallback.UnitSentence__c = '円';
    fallback.DigitalLicenceFeeLabel__c = 'デジタルライセンス料';
    fallback.ConsultingFeeLabel__c = 'コンサルティング料';
    fallback.FeedbackCoacingFeeLabel__c = 'フィードバックコーチング料';
    fallback.OtherFeeLavel__c = 'その他';
    fallback.NoteSentenceLabel__c = '特記事項';
    fallback.NoteSencente__c = resolveFallbackNoteText(history);
    fallback.OwnerLabel__c = '担当：';
    if (
      history != null &&
      history.ContractService__r != null &&
      history.ContractService__r.TaxPercent__c != null
    ) {
      fallback.Tax__c = TaxCalculationUtil.fromPercentFieldStorage(
        history.ContractService__r.TaxPercent__c
      );
    }
    return fallback;
  }

  private static String resolveFallbackNoteText(ContractHistory__c history) {
    if (history == null) {
      return '';
    }
    if (String.isNotBlank(history.Note__c)) {
      return history.Note__c;
    }
    if (
      history.EstimateNoteMaster__r != null &&
      String.isNotBlank(history.EstimateNoteMaster__r.NoteText__c)
    ) {
      return history.EstimateNoteMaster__r.NoteText__c;
    }
    return '';
  }

  @TestVisible
  private static void buildDisplayValues(DocumentContext context) {
    ContractHistory__c history = context.history;
    EstimateSetting__c setting = context.estimateSetting;

    if (setting != null && String.isNotBlank(setting.ToCompanyName__c)) {
      context.toCompanyNameDisplay = setting.ToCompanyName__c;
    } else {
      context.toCompanyNameDisplay = resolveAddresseeName(history);
    }

    if (setting != null && String.isNotBlank(setting.OwnerName__c)) {
      context.ownerNameDisplay = setting.OwnerName__c;
    } else if (
      history != null &&
      history.Opportunity__r != null &&
      history.Opportunity__r.Owner != null &&
      String.isNotBlank(history.Opportunity__r.Owner.Name)
    ) {
      context.ownerNameDisplay = history.Opportunity__r.Owner.Name;
    } else {
      context.ownerNameDisplay = '';
    }

    if (setting != null && String.isNotBlank(setting.EstimateDateSentence__c)) {
      context.estimateDateDisplay = setting.EstimateDateSentence__c;
    } else {
      Date estimateDate = history == null
        ? Date.today()
        : history.EstimateIssueDate__c != null
            ? history.EstimateIssueDate__c
            : history.EstimateDate__c != null
                ? history.EstimateDate__c
                : Date.today();
      context.estimateDateDisplay = formatEstimateDateWithWeekday(estimateDate);
    }

    if (
      setting != null &&
      String.isNotBlank(setting.TermFeeStartDateSencence__c)
    ) {
      context.termFeeStartDateDisplay = setting.TermFeeStartDateSencence__c;
    } else {
      Date earliest = getEarliestProductStartDate(history == null ? null : history.Id);
      context.termFeeStartDateDisplay = earliest == null
        ? ''
        : formatEstimateDateWithWeekday(earliest);
    }
  }

  private static Date getEarliestProductStartDate(Id contractHistoryId) {
    if (contractHistoryId == null) {
      return null;
    }
    List<ContractProduct__c> products = [
      SELECT StartDate__c
      FROM ContractProduct__c
      WHERE ContractHistory__c = :contractHistoryId AND StartDate__c != NULL
      WITH SYSTEM_MODE
      ORDER BY StartDate__c ASC
      LIMIT 1
    ];
    return products.isEmpty() ? null : products[0].StartDate__c;
  }

  @TestVisible
  private static String formatEstimateDateWithWeekday(Date value) {
    if (value == null) {
      return '';
    }
    Date knownSunday = Date.newInstance(1900, 1, 7);
    Integer daysBetween = knownSunday.daysBetween(value);
    Integer dayIdx = Math.mod(daysBetween, 7);
    if (dayIdx < 0) {
      dayIdx += 7;
    }
    List<String> daysJP = new List<String>{
      '日',
      '月',
      '火',
      '水',
      '木',
      '金',
      '土'
    };
    Datetime dt = Datetime.newInstance(value.year(), value.month(), value.day());
    return dt.format('yyyy/M/d') + '(' + daysJP[dayIdx] + ')';
  }

  @TestVisible
  private static String generateEstimateNumber(ContractHistory__c history) {
    if (history != null && String.isNotBlank(history.Name)) {
      return history.Name.trim();
    }
    String datePart = Date.today().format().replace('/', '');
    return 'HZ-' + datePart + '-001';
  }
}
