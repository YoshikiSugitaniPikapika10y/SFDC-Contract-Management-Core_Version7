import { LightningElement, api } from "lwc";
import { CloseActionScreenEvent } from "lightning/actions";
import {
  NavigationMixin,
  openContentDocumentFilePreview
} from "c/orderWizardNavigation";

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
export default class EstimateIssueRecordAction extends NavigationMixin(
  LightningElement
) {
  @api recordId;
  showSend = false;
  completionNote = "";

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

  handleClose() {
    this.dispatchEvent(new CloseActionScreenEvent());
  }

  /** 仕様: Core 第4.8節・第0.3節。送付中も発行ページは残す。 */
  get issueSurfaceClass() {
    return this.showSend === true
      ? "issue-surface issue-surface_held"
      : "issue-surface";
  }

  /** 仕様: Core 第0.3節・第4.8節。送付だけを閉じ、発行面に留まる。成功の1文は発行面に残す。 */
  handleSendPanelClose(event) {
    const sent = event?.detail?.sent === true;
    this.showSend = false;
    this.completionNote = sent ? "見積を送付しました。" : "";
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
      // 仕様: Core 第4.8節・第7.10節。標準 Files のオーバーレイ。ダウンロードにも発行面の差し替えにもしない。
      if (documentId) {
        openContentDocumentFilePreview(this, documentId);
      }
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
      this.completionNote = "";
      this.showSend = true;
    }
  }
}
