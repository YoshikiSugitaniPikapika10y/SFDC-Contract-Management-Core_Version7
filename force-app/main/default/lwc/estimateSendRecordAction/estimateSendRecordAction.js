import { LightningElement, api } from "lwc";
import { CloseActionScreenEvent } from "lightning/actions";
import { RefreshEvent } from "lightning/refresh";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import LightningConfirm from "lightning/confirm";
import getBoardContext from "@salesforce/apex/EstimateSendBoardController.getBoardContext";
import getRecordActionEstimate from "@salesforce/apex/EstimateSendBoardController.getRecordActionEstimate";
import previewEstimate from "@salesforce/apex/EstimateSendBoardController.previewEstimateFromRecordPage";
import sendEstimate from "@salesforce/apex/EstimateSendBoardController.sendEstimateFromRecordPage";
import hasSendEstimates from "@salesforce/customPermission/Loop_05_Can_SendEstimate";

const INITIAL_ATTACHMENT_KEY = "cmc.estimateSend.initialContentDocumentId";
const ATTACHMENT_NEW = "NEW";
/** 仕様: Core 第7.10節 */
const SEND_FAILURE_RETRY_NOTE =
  "失敗のあと送り直すと、先のメールが届いていることがある";

export default class EstimateSendRecordAction extends LightningElement {
  _recordId;
  estimate;
  documentTemplateKey = "";
  emailTemplateApiName = "";
  documentTemplateOptions = [];
  emailTemplateOptions = [];
  fromLabel = "";
  fromChoice = "Self";
  operatorEmail = "";
  orgFromLabel = "";
  orgFromResolved = false;
  toAddresses = "";
  ccAddresses = "";
  bccAddresses = "";
  subject = "";
  body = "";
  fileName = "";
  newIssueFileName = "";
  attachmentId = "";
  attachmentOptions = [];
  preferredAttachmentId = "";
  errorMessage = "";
  isLoading = false;
  isSending = false;

  @api
  get recordId() {
    return this._recordId;
  }

  set recordId(value) {
    if (value && value !== this._recordId) {
      this._recordId = value;
      this.load();
    }
  }

  get fromChoiceOptions() {
    return [
      { label: "自分", value: "Self" },
      { label: "組織", value: "Org" }
    ];
  }

  get isResend() {
    return Boolean(this.estimate?.estimateSentAt);
  }

  get sendButtonLabel() {
    return this.isResend ? "再送する" : "送付する";
  }

  get canSendEstimates() {
    return hasSendEstimates === true;
  }

  get sendFailureRetryNote() {
    return SEND_FAILURE_RETRY_NOTE;
  }

  /** 仕様: Core 第7.10節。空の区切りは無視。不正があれば送れない。 */
  hasInvalidEmailList(raw) {
    if (raw == null || String(raw).trim() === "") {
      return false;
    }
    if (String(raw).length > 255) {
      return true;
    }
    const pattern =
      /^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$/;
    for (const candidate of String(raw).split(",")) {
      const address = candidate.trim();
      if (!address) {
        continue;
      }
      if (!pattern.test(address)) {
        return true;
      }
    }
    return false;
  }

  get sendDisabled() {
    return (
      this.isLoading ||
      this.isSending ||
      this.estimate?.sendable !== true ||
      !this.documentTemplateKey ||
      !this.emailTemplateApiName ||
      !this.toAddresses ||
      !this.attachmentId ||
      this.isBlankText(this.fileName) ||
      this.hasInvalidEmailList(this.ccAddresses) ||
      this.hasInvalidEmailList(this.bccAddresses) ||
      (this.fromChoice === "Org" && this.orgFromResolved !== true) ||
      (this.fromChoice === "Self" && this.isBlankText(this.operatorEmail))
    );
  }

  /** 仕様: Core 第4.8節、第11.3.2節、第1.1.10節。組織を選んだとき未解決なら送れない。 */
  get isOrgFromUnresolved() {
    return this.fromChoice === "Org" && this.orgFromResolved !== true;
  }

  /** 仕様: Core 第4.8節、第7.10節、第11.3.2節。自分を選んで操作者メールが空なら送れない。 */
  get isSelfFromUnresolved() {
    return this.fromChoice === "Self" && this.isBlankText(this.operatorEmail);
  }

  /** 仕様: Core 第7.10節、第1.1.10節。添付名が空なら送れない。 */
  isBlankText(value) {
    return value == null || String(value).trim() === "";
  }

  get showDocumentTemplatePicker() {
    return this.attachmentId === ATTACHMENT_NEW;
  }

  get showExistingFilePreview() {
    return Boolean(this.attachmentId) && this.attachmentId !== ATTACHMENT_NEW;
  }

  get existingFilePreviewUrl() {
    return this.showExistingFilePreview
      ? `/lightning/r/ContentDocument/${this.attachmentId}/view`
      : "";
  }

  get unavailableMessage() {
    if (!this.estimate) {
      return "";
    }
    if (this.estimate.sendable !== true) {
      return this.estimate.sendableReason || "この見積は送付できません。";
    }
    if (!this.documentTemplateKey) {
      return "利用できる見積帳票テンプレートがありません。";
    }
    if (!this.emailTemplateApiName) {
      return "利用できる見積送付メールがありません。";
    }
    return "";
  }

  get hasUnavailableMessage() {
    return Boolean(this.unavailableMessage);
  }

  async load() {
    if (!this._recordId) {
      return;
    }
    if (this.canSendEstimates !== true) {
      this.estimate = null;
      this.errorMessage = "見積を送る権限がありません。";
      this.isLoading = false;
      return;
    }
    this.isLoading = true;
    this.errorMessage = "";
    this.preferredAttachmentId = this.consumePreferredAttachmentId();
    try {
      const [context, estimate] = await Promise.all([
        getBoardContext(),
        getRecordActionEstimate({ historyId: this._recordId })
      ]);
      this.estimate = estimate;
      this.documentTemplateOptions = (
        context?.documentTemplateOptions || []
      ).map((item) => ({ label: item.label, value: item.value }));
      this.emailTemplateOptions = (context?.emailTemplateOptions || []).map(
        (item) => ({
          label: item.label,
          value: item.value
        })
      );
      this.documentTemplateKey = context?.defaultDocumentTemplateKey || "";
      this.emailTemplateApiName = context?.defaultEmailTemplateApiName || "";
      this.fromChoice = context?.defaultFromChoice || "Self";
      this.operatorEmail = context?.operatorEmail || "";
      this.orgFromLabel = context?.orgFromLabel || "";
      this.orgFromResolved = false;
      if (this.documentTemplateKey && this.emailTemplateApiName) {
        await this.reloadPreview();
      }
    } catch (error) {
      this.estimate = null;
      this.errorMessage = this.toMessage(error);
    } finally {
      this.isLoading = false;
    }
  }

  async reloadPreview() {
    const previousAttachmentId = this.attachmentId;
    const previousFileName = this.fileName;
    const preview = await previewEstimate({
      historyId: this._recordId,
      documentTemplateKey: this.documentTemplateKey,
      emailTemplateApiName: this.emailTemplateApiName,
      fromChoice: this.fromChoice,
      preferredAttachmentId:
        this.attachmentId || this.preferredAttachmentId || null
    });
    this.fromLabel = preview?.fromLabel || "";
    this.fromChoice = preview?.fromChoice || this.fromChoice;
    this.operatorEmail = preview?.operatorEmail || this.operatorEmail;
    this.toAddresses = preview?.toAddresses || "";
    this.ccAddresses = preview?.ccAddresses || "";
    this.bccAddresses = preview?.bccAddresses || "";
    this.subject = preview?.subject || "";
    this.body = preview?.body || "";
    this.attachmentOptions = (preview?.attachmentOptions || []).map((item) => ({
      label: item.label,
      value: item.value,
      fileName: item.fileName
    }));
    this.attachmentId = preview?.attachmentId || "";
    this.newIssueFileName = preview?.newIssueFileName || "";
    // 仕様: Core 第7.10節。帳票変更のファイル名やり直しは新しく発行するときだけ。
    if (
      this.attachmentId &&
      this.attachmentId !== ATTACHMENT_NEW &&
      this.attachmentId === previousAttachmentId &&
      previousFileName
    ) {
      this.fileName = previousFileName;
    } else {
      this.fileName = preview?.fileName || "";
    }
    this.documentTemplateKey =
      preview?.documentTemplateKey || this.documentTemplateKey;
    this.emailTemplateApiName =
      preview?.emailTemplateApiName || this.emailTemplateApiName;
  }

  // 仕様: Core 第7.10節
  async handleDocumentTemplateChange(event) {
    const next = event.detail.value;
    const confirmed = await this.confirmRemerge();
    if (!confirmed) {
      event.target.value = this.documentTemplateKey;
      return;
    }
    this.documentTemplateKey = next;
    await this.reloadPreview();
  }

  // 仕様: Core 第7.10節
  async handleEmailTemplateChange(event) {
    const next = event.detail.value;
    const confirmed = await this.confirmRemerge();
    if (!confirmed) {
      event.target.value = this.emailTemplateApiName;
      return;
    }
    this.emailTemplateApiName = next;
    await this.reloadPreview();
  }

  // 仕様: Core 第4.8節。From は組織か自分。差し込みはやり直さない。
  async handleFromChoiceChange(event) {
    const next = event.detail.value;
    this.fromChoice = next;
    this.errorMessage = "";
    if (next === "Self") {
      this.orgFromResolved = false;
      this.fromLabel = this.operatorEmail || "";
      return;
    }
    this.orgFromResolved = false;
    try {
      const preview = await previewEstimate({
        historyId: this._recordId,
        documentTemplateKey: this.documentTemplateKey,
        emailTemplateApiName: this.emailTemplateApiName,
        fromChoice: next
      });
      this.fromLabel = preview?.fromLabel || "";
      this.orgFromResolved = !this.isBlankText(this.fromLabel);
    } catch (error) {
      this.fromLabel = this.orgFromLabel || "";
      this.orgFromResolved = false;
      this.errorMessage = this.toMessage(error);
    }
  }

  // 仕様: Core 第7.10節
  handleAttachmentChange(event) {
    const next = event.detail.value;
    this.attachmentId = next;
    if (next === ATTACHMENT_NEW) {
      this.fileName = this.newIssueFileName || "";
      return;
    }
    const option = (this.attachmentOptions || []).find(
      (item) => item.value === next
    );
    this.fileName = option?.fileName || "";
  }

  consumePreferredAttachmentId() {
    try {
      const stored = sessionStorage.getItem(INITIAL_ATTACHMENT_KEY);
      if (stored) {
        sessionStorage.removeItem(INITIAL_ATTACHMENT_KEY);
        return stored;
      }
    } catch (e) {
      return "";
    }
    return "";
  }

  async confirmRemerge() {
    return LightningConfirm.open({
      label: "テンプレートを変更",
      message:
        this.attachmentId === ATTACHMENT_NEW
          ? "帳票またはメールを変えると、差し込みとファイル名をやり直します。加筆は捨てます。"
          : "メールを変えると差し込みをやり直します。既存添付は作り直しません。加筆は捨てます。",
      variant: "header"
    });
  }

  handleDraftChange(event) {
    const { name, value } = event.target;
    if (name === "toAddresses") {
      return;
    }
    this[name] = value;
  }

  handleCancel() {
    this.dispatchEvent(
      new CustomEvent("panelclose", { bubbles: true, composed: true })
    );
    this.dispatchEvent(new CloseActionScreenEvent());
  }

  async handleSend() {
    if (this.sendDisabled) {
      return;
    }
    this.isSending = true;
    this.errorMessage = "";
    try {
      await sendEstimate({
        historyId: this._recordId,
        documentTemplateKey: this.documentTemplateKey,
        emailTemplateApiName: this.emailTemplateApiName || null,
        expectedToken: this.estimate.lastModifiedToken,
        draft: {
          toAddresses: this.toAddresses,
          ccAddresses: this.ccAddresses,
          bccAddresses: this.bccAddresses,
          subject: this.subject,
          body: this.body,
          fileName: this.fileName,
          fromChoice: this.fromChoice,
          attachmentId: this.attachmentId
        }
      });
      this.dispatchEvent(
        new ShowToastEvent({
          title: this.isResend ? "見積を再送しました" : "見積を送付しました",
          message: this.toAddresses,
          variant: "success"
        })
      );
      this.dispatchEvent(new RefreshEvent());
      this.dispatchEvent(
        new CustomEvent("panelclose", { bubbles: true, composed: true })
      );
      this.dispatchEvent(new CloseActionScreenEvent());
    } catch (error) {
      const message = this.toMessage(error);
      await this.load();
      this.errorMessage = message;
    } finally {
      this.isSending = false;
    }
  }

  toMessage(error) {
    return (
      error?.body?.message ||
      error?.message ||
      "見積を送付できませんでした。"
    );
  }
}
