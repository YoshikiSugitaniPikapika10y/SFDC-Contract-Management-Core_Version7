import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { CloseActionScreenEvent } from "lightning/actions";
import { getRecord } from "lightning/uiRecordApi";
import getDocumentDefaults from "@salesforce/apex/EstimateCreateController.getDocumentDefaults";
import hasEstimate from "@salesforce/customPermission/Loop_03_Can_Estimate";
import hasIssueEstimate from "@salesforce/customPermission/Loop_04_Can_IssueEstimate";
import hasSendEstimates from "@salesforce/customPermission/Loop_05_Can_SendEstimate";
import HISTORY_STATUS_FIELD from "@salesforce/schema/ContractHistory__c.historystatus__c";
import { resizeQuickActionPanel } from "c/quickActionPanelResize";
import { openContentDocumentFilePreview } from "c/orderWizardNavigation";

const STATUS_ESTIMATE = "Estimate";
const MODE_UNUSED = "Unused";
const MODE_PDF_AND_EMAIL = "PdfAndEmail";
const OBJECT_API_NAME = "ContractHistory__c";
const ISSUE_MSG_SOURCE = "EstimateDocumentIssue";
const INITIAL_ATTACHMENT_KEY = "cmc.estimateSend.initialContentDocumentId";

const QUICK_ACTIONS = {
  edit: "ContractHistory__c.EstimateEdit",
  copy: "ContractHistory__c.EstimateCopy",
  archive: "ContractHistory__c.Estimate_Archive",
  send: "ContractHistory__c.Estimate_Send"
};

/** 仕様: Core 第4.3.1節、第4.3.11節。シェルは画面見た目第2節（受注と同じ Quick Action オーバーレイ）。 */
export default class EstimateActionHub extends NavigationMixin(LightningElement) {
  @api recordId;

  historyStatus = "";
  estimateSendMode = "";
  showIssueFrame = false;
  _onIssueMessage;

  @wire(getRecord, { recordId: "$recordId", fields: [HISTORY_STATUS_FIELD] })
  wiredHistory({ data, error }) {
    if (data) {
      this.historyStatus = data.fields?.historystatus__c?.value || "";
    } else if (error) {
      this.historyStatus = "";
    }
  }

  // 仕様: Core 第4.3.11節。マスタは画面を開いた時に最新。設定wireだけcacheable。
  connectedCallback() {
    this.loadDocumentDefaults();
    this._onIssueMessage = (event) => this.handleIssueFrameMessage(event);
    window.addEventListener("message", this._onIssueMessage);
  }

  disconnectedCallback() {
    if (this._onIssueMessage) {
      window.removeEventListener("message", this._onIssueMessage);
    }
  }

  renderedCallback() {
    resizeQuickActionPanel(this, this.showIssueFrame ? "large" : "confirm");
  }

  loadDocumentDefaults() {
    getDocumentDefaults()
      .then((data) => {
        this.estimateSendMode = data?.estimateSendMode || "";
      })
      .catch(() => {
        this.estimateSendMode = "";
      });
  }

  get isEstimate() {
    return this.historyStatus === STATUS_ESTIMATE;
  }

  get showEdit() {
    return this.isEstimate && hasEstimate === true;
  }

  get showCopy() {
    return this.isEstimate && hasEstimate === true;
  }

  get showArchive() {
    return this.isEstimate && hasEstimate === true;
  }

  get showIssue() {
    return (
      this.isEstimate &&
      hasIssueEstimate === true &&
      Boolean(this.estimateSendMode) &&
      this.estimateSendMode !== MODE_UNUSED
    );
  }

  get showSend() {
    return (
      this.isEstimate &&
      hasSendEstimates === true &&
      this.estimateSendMode === MODE_PDF_AND_EMAIL
    );
  }

  get visibleActions() {
    const rows = [];
    if (this.showEdit) {
      rows.push({ key: "edit", label: "編集" });
    }
    if (this.showCopy) {
      rows.push({ key: "copy", label: "コピー" });
    }
    if (this.showArchive) {
      rows.push({ key: "archive", label: "アーカイブ" });
    }
    if (this.showIssue) {
      rows.push({ key: "issue", label: "見積書発行" });
    }
    if (this.showSend) {
      rows.push({ key: "send", label: "見積を送る" });
    }
    return rows;
  }

  get hasVisibleActions() {
    return this.visibleActions.length > 0;
  }

  get issueFrameUrl() {
    if (!this.recordId) {
      return "";
    }
    return `/apex/EstimateDocumentIssue?id=${encodeURIComponent(this.recordId)}`;
  }

  get showActionList() {
    return !this.showIssueFrame;
  }

  handleCancel() {
    if (this.showIssueFrame) {
      this.showIssueFrame = false;
      return;
    }
    this.dispatchEvent(new CloseActionScreenEvent());
  }

  get cancelLabel() {
    return this.showIssueFrame ? "戻る" : "閉じる";
  }

  // 仕様: Core 第4.3.1節。シェルは受注と同じレコード上オーバーレイ（画面見た目第2節）。
  handleSelect(event) {
    const key = event.currentTarget?.dataset?.key;
    if (!key || !this.recordId) {
      return;
    }
    if (key === "issue") {
      this.showIssueFrame = true;
      return;
    }
    const apiName = QUICK_ACTIONS[key];
    if (!apiName) {
      return;
    }
    this.openRecordQuickAction(apiName);
  }

  // 仕様: Core 第4.8節・第7.10節。発行 iframe からの filePreview／このファイルを送る。
  handleIssueFrameMessage(event) {
    if (event.origin !== window.location.origin) {
      return;
    }
    const data = event.data;
    if (!data || data.source !== ISSUE_MSG_SOURCE) {
      return;
    }
    if (data.action === "filePreview") {
      openContentDocumentFilePreview(this, data.documentId);
      return;
    }
    if (data.action === "sendThisFile") {
      if (data.documentId) {
        try {
          sessionStorage.setItem(INITIAL_ATTACHMENT_KEY, data.documentId);
        } catch (e) {
          // sessionStorage が使えない環境でも送付画面は開く
        }
      }
      this.showIssueFrame = false;
      this.openRecordQuickAction(QUICK_ACTIONS.send);
    }
  }

  openRecordQuickAction(apiName) {
    const backgroundContext = `/lightning/r/${OBJECT_API_NAME}/${this.recordId}/view`;
    this[NavigationMixin.Navigate](
      {
        type: "standard__quickAction",
        attributes: {
          apiName
        },
        state: {
          objectApiName: OBJECT_API_NAME,
          context: "RECORD_DETAIL",
          recordId: this.recordId,
          backgroundContext
        }
      },
      true
    );
  }
}
