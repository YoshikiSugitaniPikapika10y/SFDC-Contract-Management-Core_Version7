import { LightningElement, api } from "lwc";
import { CloseActionScreenEvent } from "lightning/actions";

const ISSUE_MESSAGE_SOURCE = "cmc-estimate-issue";
const INITIAL_ATTACHMENT_KEY = "cmc.estimateSend.initialContentDocumentId";

function salesforceId(value) {
  const text = value == null ? "" : String(value).trim();
  return /^[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?$/.test(text) ? text : "";
}

function contentDocumentIdOf(value) {
  const id = salesforceId(value);
  return id.startsWith("069") ? id : "";
}

function contentVersionIdOf(value) {
  const id = salesforceId(value);
  return id.startsWith("068") ? id : "";
}

/** 仕様: Core 第4.8節・第7.10節・第4.3.1節。発行ページの Visualforce からだけ受け取る。 */
function isVisualforceOrigin(origin) {
  if (!origin || typeof origin !== "string") {
    return false;
  }
  try {
    const host = new URL(origin).hostname;
    return (
      host.endsWith(".vf.force.com") ||
      host.endsWith(".visualforce.com") ||
      host.endsWith(".visual.force.com") ||
      host.endsWith(".vf.salesforce.com")
    );
  } catch (e) {
    return false;
  }
}

/** 仕様: Core 第4.3.1節・第4.8節・第7.10節。発行面に留まり、プレビューと送付は開いているポップアップの中で終える。 */
export default class EstimateIssueRecordAction extends LightningElement {
  @api recordId;
  showSend = false;
  previewDocumentId = "";
  previewVersionId = "";

  connectedCallback() {
    this._onIssueMessage = (event) => this.handleIssueMessage(event);
    window.addEventListener("message", this._onIssueMessage);
  }

  disconnectedCallback() {
    window.removeEventListener("message", this._onIssueMessage);
  }

  /** 仕様: Core 第4.8節・第7.10節・第4.3.1節。発行ページへ、このポップアップの住所を渡す。 */
  get issuePageUrl() {
    if (!this.recordId) {
      return "";
    }
    const parentOrigin = encodeURIComponent(window.location.origin);
    return `/apex/EstimateDocumentIssue?id=${encodeURIComponent(this.recordId)}&parentOrigin=${parentOrigin}`;
  }

  /** 仕様: Core 第4.8節・第7.10節。プレビューは発行面の上。レコード画面は移さない。 */
  get previewFrameUrl() {
    if (this.previewVersionId) {
      return `/sfc/servlet.shepherd/version/download/${this.previewVersionId}`;
    }
    if (this.previewDocumentId) {
      return `/sfc/servlet.shepherd/document/download/${this.previewDocumentId}`;
    }
    return "";
  }

  get showPreview() {
    return this.previewFrameUrl !== "";
  }

  handleClose() {
    this.dispatchEvent(new CloseActionScreenEvent());
  }

  /** 仕様: Core 第4.8節・第7.10節。プレビューを閉じると発行面に戻る。ポップアップは閉じない。 */
  handleClosePreview() {
    this.previewDocumentId = "";
    this.previewVersionId = "";
  }

  /** 仕様: Core 第4.8節・第7.10節・第4.3.1節。プレビューは発行面の上。送付は同じポップアップの見積送付。 */
  handleIssueMessage(event) {
    if (!isVisualforceOrigin(event.origin)) {
      return;
    }
    const data = event.data;
    if (!data || data.source !== ISSUE_MESSAGE_SOURCE) {
      return;
    }
    const documentId = contentDocumentIdOf(data.contentDocumentId);
    const versionId = contentVersionIdOf(data.contentVersionId);
    if (!documentId && !versionId) {
      return;
    }
    if (data.action === "preview") {
      this.previewDocumentId = documentId;
      this.previewVersionId = versionId;
      return;
    }
    if (data.action === "send" && this.recordId) {
      if (documentId) {
        try {
          sessionStorage.setItem(INITIAL_ATTACHMENT_KEY, documentId);
        } catch (e) {
          // 仕様: Core 第7.10節。渡せないときは通常の初期値。送付画面は開く。
        }
      }
      this.previewDocumentId = "";
      this.previewVersionId = "";
      this.showSend = true;
    }
  }
}
