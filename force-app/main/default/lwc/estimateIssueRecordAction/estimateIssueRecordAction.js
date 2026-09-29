import { LightningElement, api } from "lwc";
import { CloseActionScreenEvent } from "lightning/actions";
import {
  NavigationMixin,
  openContentDocumentFilePreview
} from "c/orderWizardNavigation";

const ISSUE_MESSAGE_SOURCE = "cmc-estimate-issue";
const INITIAL_ATTACHMENT_KEY = "cmc.estimateSend.initialContentDocumentId";

/** 仕様: Core 第4.3.1節・第4.8節・第7.10節。発行面に留まり、プレビューと送付でページを移さない。 */
export default class EstimateIssueRecordAction extends NavigationMixin(
  LightningElement
) {
  @api recordId;
  showSend = false;

  connectedCallback() {
    this._onIssueMessage = (event) => this.handleIssueMessage(event);
    window.addEventListener("message", this._onIssueMessage);
  }

  disconnectedCallback() {
    window.removeEventListener("message", this._onIssueMessage);
  }

  get issuePageUrl() {
    return this.recordId
      ? `/apex/EstimateDocumentIssue?id=${encodeURIComponent(this.recordId)}`
      : "";
  }

  handleClose() {
    this.dispatchEvent(new CloseActionScreenEvent());
  }

  /** 仕様: Core 第4.8節・第7.10節。プレビューは発行面の上。送付は同じ画面の見積送付。 */
  handleIssueMessage(event) {
    if (event.origin !== window.location.origin) {
      return;
    }
    const data = event.data;
    if (!data || data.source !== ISSUE_MESSAGE_SOURCE) {
      return;
    }
    const documentId =
      data.contentDocumentId == null ? "" : String(data.contentDocumentId);
    if (!documentId) {
      return;
    }
    if (data.action === "preview") {
      openContentDocumentFilePreview(this, documentId);
      return;
    }
    if (data.action === "send" && this.recordId) {
      try {
        sessionStorage.setItem(INITIAL_ATTACHMENT_KEY, documentId);
      } catch (e) {
        return;
      }
      this.showSend = true;
    }
  }
}
