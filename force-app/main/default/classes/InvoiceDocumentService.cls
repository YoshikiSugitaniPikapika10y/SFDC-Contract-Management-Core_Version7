/**
 * 請求スナップショットから請求書表示データを組み立て、PDF を発行・保存する。
 */
public without sharing class InvoiceDocumentService {
  /** 仕様: Core 第0.1節、第7.10節、第7.11節 */
  @TestVisible
  private static final String STATUS_REQUIRED_MESSAGE = '請求書の表示・発行は請求取引状態が確定済みの請求のみ利用できます。';

  public class DocumentContext {
    public Invoice__c invoice { get; set; }
    public List<InvoiceLine__c> lines { get; set; }
    public ContractDocumentSetting__c documentSetting { get; set; }
    public String addressee { get; set; }
    public String invoiceDateLabel { get; set; }
    public String paymentDueDateLabel { get; set; }
    public String invoiceDatePrint { get; set; }
    public String paymentDueDatePrint { get; set; }
    public String taxBaseLabel { get; set; }
    public String taxRateLabel { get; set; }
    public List<LinePrint> linePrints { get; set; }
    public Decimal amountExcludingTax { get; set; }
    public Decimal taxAmount { get; set; }
    public Decimal amountIncludingTax { get; set; }
  }

  public class LinePrint {
    public String content { get; set; }
    public String period { get; set; }
    public Decimal quantity { get; set; }
    public String unit { get; set; }
    public Decimal unitPrice { get; set; }
    public Decimal amount { get; set; }
  }

  public class IssueResult {
    public Id contentVersionId;
    public Id contentDocumentId;
    public String fileName;
    public String templateKey;
    public String visualforcePage;
  }

  public class InvoiceDocumentException extends Exception {
  }

  public static DocumentContext loadContext(Id invoiceId) {
    return loadContext(invoiceId, null);
  }

  /**
   * 仕様: Core 第12.4節、第7.10節。
   * ロック済み請求があれば取り直さない。
   */
  public static DocumentContext loadContext(
    Id invoiceId,
    Invoice__c knownInvoice
  ) {
    if (invoiceId == null) {
      throw new InvoiceDocumentException('請求IDが指定されていません。');
    }
    Invoice__c invoice;
    if (
      knownInvoice != null &&
      knownInvoice.Id == invoiceId &&
      knownInvoice.isSet(Invoice__c.Amount__c)
    ) {
      invoice = knownInvoice;
    } else {
      // 仕様: Core 第7.1節・第7.10節。備考位置は Memo__c。Name、日付、金額、宛名、支払条件もこの行を読む。
      List<Invoice__c> invoices = [
        SELECT
          Id,
          Name,
          InvoiceDate__c,
          PaymentScheduledDate__c,
          InvoiceTransactionStatus__c,
          BillingAccountSnapShot__c,
          BillingAddresseeSnapShot__c,
          PaymentTermMethodSnapShot__c,
          Amount__c,
          TaxAmount__c,
          TaxInclusiveAmount__c,
          TaxPercent__c,
          Memo__c
        FROM Invoice__c
        WHERE Id = :invoiceId
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      if (invoices.isEmpty()) {
        throw new InvoiceDocumentException('請求が見つかりません。');
      }
      invoice = invoices[0];
    }
    if (!InvoiceTransactionStatusService.isConfirmed(invoice)) {
      throw new InvoiceDocumentException(STATUS_REQUIRED_MESSAGE);
    }

    DocumentContext context = new DocumentContext();
    context.invoice = invoice;
    context.lines = [
      SELECT
        Id,
        Name,
        ProductName__c,
        ProductCodeSnapShot__c,
        PeriodLabel__c,
        Unit__c,
        Quantity__c,
        UnitPrice__c,
        Amount__c,
        DocumentSortOrder__c,
        ServicePeriodStartDate__c,
        ServicePeriodEndDate__c
      FROM InvoiceLine__c
      WHERE Invoice__c = :invoiceId
      WITH SYSTEM_MODE
      ORDER BY Name ASC
    ];
    // 仕様: Core 第4.5.3節、第7.7.0節
    DocumentSortOrderService.sortInvoiceLines(context.lines);
    context.documentSetting = loadDocumentSetting();
    context.addressee = nvl(invoice.BillingAddresseeSnapShot__c);
    context.invoiceDateLabel = formatDisplayDate(invoice.InvoiceDate__c);
    context.paymentDueDateLabel = formatDisplayDate(
      invoice.PaymentScheduledDate__c
    );
    // 仕様: Core 第7.1節。印字は yyyy年M月d日。空は空。今日で埋めない。
    context.invoiceDatePrint = formatLooseDate(invoice.InvoiceDate__c);
    context.paymentDueDatePrint = formatLooseDate(
      invoice.PaymentScheduledDate__c
    );
    applyTaxPrintLabels(context, invoice);
    context.linePrints = toLinePrints(context.lines);
    context.amountExcludingTax = nvl(invoice.Amount__c);
    context.taxAmount = nvl(invoice.TaxAmount__c);
    context.amountIncludingTax = invoice.TaxInclusiveAmount__c == null
      ? context.amountExcludingTax + context.taxAmount
      : invoice.TaxInclusiveAmount__c;
    return context;
  }

  /** 仕様: Core 第7.7.3節、第7.10節、第11.3.1節、第11.3.2節。キー空は発行できない。 */
  public static IssueResult issueInvoiceDocument(
    Id invoiceId,
    String templateKey
  ) {
    return issueInvoiceDocument(invoiceId, templateKey, null);
  }

  /** 仕様: Core 第7.10節。attachmentFileName は「新しく発行する」の送付添付名。 */
  public static IssueResult issueInvoiceDocument(
    Id invoiceId,
    String templateKey,
    String attachmentFileName
  ) {
    return issueInvoiceDocument(
      invoiceId,
      templateKey,
      attachmentFileName,
      null
    );
  }

  /**
   * 仕様: Core 第12.4節、第7.10節。
   * ロック済み請求があれば loadContext で取り直さない。
   */
  public static IssueResult issueInvoiceDocument(
    Id invoiceId,
    String templateKey,
    String attachmentFileName,
    Invoice__c knownInvoice
  ) {
    ContractDocumentTemplateService.TemplateDefinition template = resolveIssueTemplate(
      templateKey
    );
    try {
      if (
        ContractDocumentSettingService.requireSendMode('Invoice') ==
        ContractDocumentSettingService.MODE_UNUSED
      ) {
        throw new InvoiceDocumentException(
          '請求書設定が使わないのため、発行も送付もできません。'
        );
      }
      ContractDocumentSettingService.assertRequiredCompanyFields();
    } catch (ContractDocumentSettingService.SettingException ex) {
      throw new InvoiceDocumentException(
        ContractDocumentSettingService.withDocumentSendHeading(ex.getMessage())
      );
    }
    DocumentContext context = loadContext(invoiceId, knownInvoice);
    String fileName = String.isNotBlank(attachmentFileName)
      ? attachmentFileName.trim()
      : buildFileName(context.invoice, template);
    Blob pdfBody = generatePdfBlob(invoiceId, template);
    Id contentVersionId = savePdfToInvoice(invoiceId, fileName, pdfBody);

    IssueResult result = new IssueResult();
    result.contentVersionId = contentVersionId;
    result.contentDocumentId = [
      SELECT ContentDocumentId
      FROM ContentVersion
      WHERE Id = :contentVersionId
      WITH SYSTEM_MODE
      LIMIT 1
    ]
    .ContentDocumentId;
    result.fileName = fileName;
    result.templateKey = template.templateKey;
    result.visualforcePage = template.visualforcePage;
    if (ContractOperationLogService.suppressIssueLog != true) {
      ContractOperationLogService.write(
        'InvoicePdfIssue',
        null,
        'Invoice__c',
        String.valueOf(invoiceId)
      );
    }
    return result;
  }

  public static IssueResult issueInvoiceDocument(Id invoiceId) {
    return issueInvoiceDocument(invoiceId, null);
  }

  public static Blob generatePdfBlob(Id invoiceId, String templateKey) {
    ContractDocumentTemplateService.TemplateDefinition template = resolveIssueTemplate(
      templateKey
    );
    loadContext(invoiceId);
    return generatePdfBlob(invoiceId, template);
  }

  public static Blob generatePdfBlob(Id invoiceId) {
    return generatePdfBlob(invoiceId, (String) null);
  }

  /** 仕様: Core 第11.3.2節、日付仕様 第8章 */
  public static String buildFileName(
    Invoice__c invoice,
    ContractDocumentTemplateService.TemplateDefinition template
  ) {
    String pattern = template == null ||
      String.isBlank(template.fileNamePattern)
      ? '{TemplateKey}_{Title}_{yyyyMMdd}.pdf'
      : template.fileNamePattern;
    Date targetDate = invoice != null &&
      invoice.InvoiceDate__c != null
      ? invoice.InvoiceDate__c
      : InvoiceTransactionStatusService.organizationToday();
    String title = resolveTitle(invoice);
    String rendered = pattern
      .replace(
        '{TemplateKey}',
        sanitizeFileName(template == null ? 'Invoice' : template.templateKey)
      )
      .replace('{Title}', sanitizeFileName(title))
      .replace(
        '{DocumentType}',
        sanitizeFileName(template == null ? 'Invoice' : template.documentType)
      )
      .replace('{yyyyMMdd}', formatCompactDate(targetDate));
    rendered = sanitizeFileName(rendered);
    return rendered.toLowerCase().endsWith('.pdf')
      ? rendered
      : rendered + '.pdf';
  }

  public static Id savePdfToInvoice(
    Id invoiceId,
    String fileName,
    Blob pdfBody
  ) {
    if (invoiceId == null) {
      throw new InvoiceDocumentException(
        '保存先の請求IDが指定されていません。'
      );
    }
    if (pdfBody == null || pdfBody.size() == 0) {
      throw new InvoiceDocumentException('PDFデータが空です。');
    }
    String normalizedFileName = String.isBlank(fileName)
      ? 'invoice.pdf'
      : fileName;
    String title = normalizedFileName.toLowerCase().endsWith('.pdf')
      ? normalizedFileName.substring(0, normalizedFileName.length() - 4)
      : normalizedFileName;
    ContentVersion version = new ContentVersion(
      Title = title,
      PathOnClient = normalizedFileName,
      VersionData = pdfBody,
      ContractDocumentIssued__c = true
    );
    SystemContextAccess.insertRecords(new List<SObject>{ version });
    Id documentId = [
      SELECT ContentDocumentId
      FROM ContentVersion
      WHERE Id = :version.Id
      WITH SYSTEM_MODE
      LIMIT 1
    ]
    .ContentDocumentId;
    SystemContextAccess.insertRecords(
      new List<SObject>{
        new ContentDocumentLink(
          ContentDocumentId = documentId,
          LinkedEntityId = invoiceId,
          ShareType = 'V',
          Visibility = 'AllUsers'
        )
      }
    );
    return version.Id;
  }

  private static ContractDocumentSetting__c loadDocumentSetting() {
    try {
      return ContractDocumentSettingService.requireOrgSetting();
    } catch (ContractDocumentSettingService.SettingException ex) {
      return new ContractDocumentSetting__c();
    }
  }

  /** 仕様: Core 第7.10節・第11.3.2節。キー空は発行できない。組織既定も既定印も使わない。 */
  private static ContractDocumentTemplateService.TemplateDefinition resolveIssueTemplate(
    String templateKey
  ) {
    try {
      return ContractDocumentTemplateService.resolveTemplate(
        ContractDocumentTemplateService.TYPE_INVOICE,
        templateKey
      );
    } catch (ContractDocumentTemplateService.DocumentTemplateException ex) {
      String message = ex.getMessage();
      if (
        message ==
        ContractDocumentSettingService.MISSING_DEFAULT_DOCUMENT_MESSAGE
      ) {
        message = ContractDocumentSettingService.withDocumentSendHeading(
          message
        );
      }
      throw new InvoiceDocumentException(message);
    }
  }

  private static Blob generatePdfBlob(
    Id invoiceId,
    ContractDocumentTemplateService.TemplateDefinition template
  ) {
    if (Test.isRunningTest()) {
      return Blob.valueOf('%PDF-1.4 invoice test');
    }
    // 仕様: Core 第4.8節・第7.10節。LWC→Apex から呼ぶ。Ajax rerender 中の getContentAsPDF は使わない。
    PageReference pdfPage = ContractDocumentTemplateService.buildPageReference(
      template,
      invoiceId
    );
    return pdfPage.getContentAsPDF();
  }

  private static String resolveTitle(Invoice__c invoice) {
    if (invoice == null) {
      return '請求書';
    }
    if (String.isNotBlank(invoice.BillingAddresseeSnapShot__c)) {
      return invoice.BillingAddresseeSnapShot__c;
    }
    return String.isBlank(invoice.Name) ? '請求書' : invoice.Name;
  }

  public static String sanitizeFileName(String value) {
    if (String.isBlank(value)) {
      return '請求書';
    }
    String sanitized = value.trim().replaceAll('[\\\\/:*?"<>|]', '_');
    sanitized = sanitized.replaceAll('\\s+', '_');
    return String.isBlank(sanitized) ? '請求書' : sanitized;
  }

  private static void applyTaxPrintLabels(
    DocumentContext context,
    Invoice__c invoice
  ) {
    context.taxBaseLabel = '';
    context.taxRateLabel = '';
    if (
      invoice == null ||
      invoice.isSet(Invoice__c.TaxPercent__c) != true ||
      invoice.TaxPercent__c == null
    ) {
      return;
    }
    // 仕様: Core 第7.1節。内訳の率は請求の保存税率。空なら率ラベルは空。
    String rateText = TaxCalculationUtil.formatTaxPercentLabel(
      TaxCalculationUtil.fromPercentFieldStorage(invoice.TaxPercent__c)
    );
    context.taxBaseLabel = rateText + '%対象(税抜)';
    context.taxRateLabel = rateText + '%消費税';
  }

  private static List<LinePrint> toLinePrints(List<InvoiceLine__c> lines) {
    List<LinePrint> prints = new List<LinePrint>();
    if (lines == null) {
      return prints;
    }
    for (InvoiceLine__c line : lines) {
      LinePrint printLine = new LinePrint();
      // 仕様: Core 第7.1節。内容は商品名。有料期間は開始日と終了日。両方空なら -。単位が空なら -。
      printLine.content = line.ProductName__c;
      printLine.period = formatInvoicePeriod(
        line.ServicePeriodStartDate__c,
        line.ServicePeriodEndDate__c
      );
      printLine.quantity = line.Quantity__c;
      printLine.unit = String.isBlank(line.Unit__c) ? '-' : line.Unit__c;
      printLine.unitPrice = line.UnitPrice__c;
      printLine.amount = line.Amount__c;
      prints.add(printLine);
    }
    return prints;
  }

  private static String formatInvoicePeriod(Date startDate, Date endDate) {
    if (startDate == null && endDate == null) {
      return '-';
    }
    return formatSlashDate(startDate) + ' - ' + formatSlashDate(endDate);
  }

  private static String formatSlashDate(Date value) {
    if (value == null) {
      return '';
    }
    return String.valueOf(value.year()) +
      '/' +
      String.valueOf(value.month()).leftPad(2, '0') +
      '/' +
      String.valueOf(value.day()).leftPad(2, '0');
  }

  private static String formatLooseDate(Date value) {
    if (value == null) {
      return '';
    }
    return String.valueOf(value.year()) +
      '年' +
      String.valueOf(value.month()) +
      '月' +
      String.valueOf(value.day()) +
      '日';
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

  private static String formatCompactDate(Date value) {
    Date target = value == null
      ? InvoiceTransactionStatusService.organizationToday()
      : value;
    return String.valueOf(target.year()) +
      String.valueOf(target.month()).leftPad(2, '0') +
      String.valueOf(target.day()).leftPad(2, '0');
  }

  private static Decimal nvl(Decimal value) {
    return value == null ? 0 : value;
  }

  private static String nvl(String value) {
    return value == null ? '' : value;
  }
}
