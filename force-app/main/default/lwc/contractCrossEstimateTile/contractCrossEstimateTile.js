import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import {
  NavigationMixin,
  openContentDocumentFilePreview
} from "c/orderWizardNavigation";
import getEstimateIssueContext from "@salesforce/apex/ContractCrossController.getEstimateIssueContext";
import previewEstimateIssueFileName from "@salesforce/apex/ContractCrossController.previewEstimateIssueFileName";
import issueEstimate from "@salesforce/apex/ContractCrossController.issueEstimate";

const INITIAL_ATTACHMENT_KEY = "cmc.estimateSend.initialContentDocumentId";

function formatAmount(value) {
  if (value == null || value === "") {
    return "";
  }
  const number = Number(value);
  if (!Number.isFinite(number)) {
    return "";
  }
  return number.toLocaleString("ja-JP");
}

function formatDate(value) {
  if (!value) {
    return "";
  }
  if (typeof value === "string") {
    return value.slice(0, 10);
  }
  return String(value);
}

function formatDateTime(value) {
  if (!value) {
    return "";
  }
  try {
    return new Date(value).toLocaleString("ja-JP");
  } catch (e) {
    return String(value);
  }
}

function periodLabel(startDate, endDate) {
  const start = formatDate(startDate);
  const end = formatDate(endDate);
  if (!start && !end) {
    return "";
  }
  return `${start}〜${end}`;
}

/** 仕様: 横断画面.md 見積書タイル */
export default class ContractCrossEstimateTile extends NavigationMixin(
  LightningElement
) {
  @api tile;
  @api accountingEnabled = false;
  @api canIssue = false;
  @api canSend = false;
  @api canOrder = false;

  showIssue = false;
  showSend = false;
  showOrder = false;
  workBusy = false;
  issueBusy = false;
  issueError = "";
  issueSucceeded = false;
  completionNote = "";
  templateKey = "";
  templateOptions = [];
  issueFileName = "";
  showSendThisFile = false;
  issuedContentDocumentId = "";
  latestIssuedContentDocumentId = "";
  companyBlockedReason = "";

  /** 仕様: 画面見た目 第4節。LWC1060 を避ける。値 true は変えない。 */
  get fromCrossWorkTrue() {
    return true;
  }

  /** 仕様: 共通基盤 第2.1節。発行・送付・受注は右の見積書タイルを作業面にする。明細表は出さない。 */
  get isCardWorkOpen() {
    return (
      this.showIssue === true ||
      this.showSend === true ||
      this.showOrder === true
    );
  }

  get historyName() {
    return this.tile?.historyName || "";
  }

  get historyId() {
    return this.tile?.id || "";
  }

  /** 仕様: 横断画面.md 第1節・第5節。数量・単価・期間を直すときは契約履歴名のレコードリンク。 */
  get historyRecordUrl() {
    return this.tile?.id
      ? `/lightning/r/ContractHistory__c/${this.tile.id}/view`
      : "";
  }

  /** 仕様: 横断画面.md 第5節 見積書タイル。Estimateだけ出す。Ordered・Archiveは出さない。 */
  get showEstimateContent() {
    return this.isEstimate;
  }

  get estimateTypeLabel() {
    return this.tile?.estimateTypeLabel || this.tile?.estimateType || "";
  }

  get showAutoRenew() {
    return this.tile?.autoRenew === true;
  }

  /** 仕様: Core 第4.8節・第1.1.10節。帳票未選択と会社情報空は発行するを止める。 */
  get issuePdfDisabled() {
    return (
      this.issueBusy === true ||
      this.isBlankText(this.templateKey) ||
      !this.isBlankText(this.companyBlockedReason)
    );
  }

  get amountLabel() {
    return formatAmount(this.tile?.amount);
  }

  get taxInclusiveLabel() {
    return formatAmount(this.tile?.taxInclusiveAmount);
  }

  get estimateDateLabel() {
    return formatDate(this.tile?.estimateDate);
  }

  get validDateLabel() {
    return formatDate(this.tile?.validDate);
  }

  get sendContactName() {
    return this.tile?.sendContactName || "";
  }

  get sentLabel() {
    return this.tile?.sentAt
      ? formatDateTime(this.tile.sentAt)
      : "未送付";
  }

  get createdDateLabel() {
    return formatDateTime(this.tile?.createdDate);
  }

  get createdByName() {
    return this.tile?.createdByName || "";
  }

  get lastModifiedByName() {
    return this.tile?.lastModifiedByName || "";
  }

  get isEstimate() {
    return this.tile?.isEstimate === true;
  }

  /** 仕様: Core 第0.1節、第4.8節。横断画面.md 第5節。見積以外は拒否。見出し・明細は出さない。 */
  get notEstimateMessage() {
    return this.tile && this.isEstimate !== true
      ? "見積書の表示・発行はステータスが見積の契約履歴のみ利用できます。"
      : "";
  }

  /** 仕様: 横断画面.md 第5節・Core 第7.10節。印付き最新。発行成功後は今回のファイル。 */
  get viewPdfDocumentId() {
    return (
      this.issuedContentDocumentId ||
      this.tile?.latestIssuedContentDocumentId ||
      this.latestIssuedContentDocumentId ||
      ""
    );
  }

  /** 仕様: 横断画面.md 第5節。請求カードと同じ。0件は出さない。 */
  get showViewPdfAction() {
    return this.isEstimate && !this.isBlankText(this.viewPdfDocumentId);
  }

  get showActionRow() {
    return this.showViewPdfAction === true || this.isCardWorkOpen !== true;
  }

  handleViewIssuedPdf() {
    openContentDocumentFilePreview(this, this.viewPdfDocumentId);
  }

  /** 仕様: Core 第4.8節。発行成功のあと、いま作ったファイルを標準 Files で確認する。 */
  get latestPdfDownloadUrl() {
    return this.issuedContentDocumentId
      ? `/sfc/servlet.shepherd/document/download/${this.issuedContentDocumentId}`
      : "";
  }

  get showLatestPdfDownload() {
    return this.issueSucceeded === true && !this.isBlankText(this.latestPdfDownloadUrl);
  }

  get previewDocumentId() {
    return this.issuedContentDocumentId || "";
  }

  get showIssuePdfPreview() {
    return this.issueSucceeded === true && !this.isBlankText(this.previewDocumentId);
  }

  handleIssuePdfPreview() {
    openContentDocumentFilePreview(this, this.previewDocumentId);
  }

  get showIssueButton() {
    return this.isEstimate && this.canIssue === true;
  }

  get showSendButton() {
    return this.isEstimate && this.canSend === true;
  }

  get sendButtonLabel() {
    return this.tile?.sentAt ? "再送する" : "見積を送る";
  }

  get showOrderButton() {
    return this.isEstimate && this.canOrder === true;
  }

  get showAccountingColumn() {
    return this.accountingEnabled === true;
  }

  get lines() {
    return (this.tile?.lines || []).map((line) => ({
      id: line.id,
      typeLabel: line.typeLabel || line.typeValue || "",
      productName: line.productName || "",
      unitPrice: formatAmount(line.unitPrice),
      unit: line.unit || "",
      quantity: line.quantity == null ? "" : String(line.quantity),
      periodLabel: periodLabel(line.startDate, line.endDate),
      cycleCount:
        line.cycleCountLabel != null && String(line.cycleCountLabel) !== ""
          ? line.cycleCountLabel
          : line.cycleCount == null
            ? ""
            : String(line.cycleCount),
      invoiceSetting: line.invoiceSetting || "",
      revenueBasis: line.revenueBasis || "",
      amount: formatAmount(line.amount)
    }));
  }

  get hasLines() {
    return this.lines.length > 0;
  }

  get lineCount() {
    return this.lines.length;
  }

  handleIssueClick() {
    this.openIssue();
  }

  /** 仕様: 共通基盤 操作5。見積書タイルから同じ送付画面。別タブへは開かない。 */
  handleSendClick() {
    if (!this.tile?.id) {
      return;
    }
    this.showIssue = false;
    this.showOrder = false;
    this.showSend = true;
    this.workBusy = false;
  }

  /** 仕様: 共通基盤 操作6。見積書タイルから同じ受注画面。別タブへは開かない。 */
  handleOrderClick() {
    if (!this.tile?.id) {
      return;
    }
    this.showIssue = false;
    this.showSend = false;
    this.showOrder = true;
    this.workBusy = false;
  }

  handleWorkBusy(event) {
    this.workBusy = event.detail?.busy === true;
  }

  // 仕様: Core 第7.10節。個別送付は終わるまで待たせる。裏では回さない。処理中は閉じない。終わったあとは閉じる。
  handleCloseWork() {
    if (this.workBusy === true) {
      return;
    }
    this.showSend = false;
    this.showOrder = false;
    this.workBusy = false;
    this.dispatchEvent(new CustomEvent("issuestatechange"));
  }

  async openIssue() {
    if (!this.tile?.id) {
      return;
    }
    this.showSend = false;
    this.showOrder = false;
    this.showIssue = true;
    this.issueBusy = true;
    this.issueError = "";
    this.issueSucceeded = false;
    this.showSendThisFile = false;
    this.issuedContentDocumentId = "";
    this.latestIssuedContentDocumentId = "";
    this.companyBlockedReason = "";
    try {
      const context = await getEstimateIssueContext({
        historyId: this.tile.id
      });
      this.templateOptions = (context?.documentTemplateOptions || []).map(
        (item) => ({ label: item.label, value: item.value })
      );
      this.templateKey = context?.defaultDocumentTemplateKey || "";
      this.issueFileName = context?.fileName || "";
      this.companyBlockedReason = context?.companyBlockedReason || "";
      this.latestIssuedContentDocumentId =
        context?.latestIssuedContentDocumentId || "";
      if (this.companyBlockedReason) {
        this.issueError = this.companyBlockedReason;
      }
    } catch (error) {
      this.issueError = this.reduceError(error);
    } finally {
      this.issueBusy = false;
    }
  }

  handleCloseIssue() {
    this.showIssue = false;
  }

  async handleTemplateChange(event) {
    this.templateKey = event.detail.value;
    if (!this.tile?.id || !this.templateKey) {
      return;
    }
    try {
      this.issueFileName = await previewEstimateIssueFileName({
        historyId: this.tile.id,
        templateKey: this.templateKey
      });
    } catch (error) {
      this.issueError = this.reduceError(error);
    }
  }

  async handleIssuePdf() {
    if (this.issuePdfDisabled || !this.tile?.id) {
      return;
    }
    this.issueBusy = true;
    this.issueError = "";
    try {
      const issued = await issueEstimate({
        historyId: this.tile.id,
        templateKey: this.templateKey
      });
      this.issueSucceeded = true;
      this.issuedContentDocumentId = issued?.contentDocumentId || "";
      this.showSendThisFile = issued?.showSendThisFile === true;
      this.completionNote = "見積書を発行しました。";
      this.dispatchEvent(new CustomEvent("issuestatechange"));
    } catch (error) {
      this.issueError = this.reduceError(error);
    } finally {
      this.issueBusy = false;
    }
  }

  handleSendThisFile() {
    if (this.issuedContentDocumentId) {
      try {
        sessionStorage.setItem(
          INITIAL_ATTACHMENT_KEY,
          this.issuedContentDocumentId
        );
      } catch (e) {
        // sessionStorage が使えない環境でも発行結果は残す
      }
    }
    this.showIssue = false;
    this.handleSendClick();
  }

  reduceError(error) {
    return (
      error?.body?.message ||
      error?.message ||
      "見積書を発行できませんでした。"
    );
  }

  isBlankText(value) {
    return !value || !String(value).trim();
  }
}
