import { LightningElement, api, wire } from "lwc";
import { CloseActionScreenEvent } from "lightning/actions";
import { getRecord } from "lightning/uiRecordApi";
import getDocumentDefaults from "@salesforce/apex/EstimateCreateController.getDocumentDefaults";
import hasEstimate from "@salesforce/customPermission/Loop_03_Can_Estimate";
import hasIssueEstimate from "@salesforce/customPermission/Loop_04_Can_IssueEstimate";
import hasSendEstimates from "@salesforce/customPermission/Loop_05_Can_SendEstimate";
import HISTORY_STATUS_FIELD from "@salesforce/schema/ContractHistory__c.historystatus__c";

const STATUS_ESTIMATE = "Estimate";
const MODE_UNUSED = "Unused";
const MODE_PDF_AND_EMAIL = "PdfAndEmail";

const QUICK_ACTIONS = {
  edit: "ContractHistory__c.EstimateEdit",
  copy: "ContractHistory__c.EstimateCopy",
  archive: "ContractHistory__c.Estimate_Archive",
  send: "ContractHistory__c.Estimate_Send"
};

/** 仕様: Core 第4.3.1節 */
export default class EstimateActionHub extends LightningElement {
  @api recordId;

  historyStatus = "";
  estimateSendMode = "";

  @wire(getRecord, { recordId: "$recordId", fields: [HISTORY_STATUS_FIELD] })
  wiredHistory({ data, error }) {
    if (data) {
      this.historyStatus = data.fields?.historystatus__c?.value || "";
    } else if (error) {
      this.historyStatus = "";
    }
  }

  @wire(getDocumentDefaults)
  wiredDefaults({ data, error }) {
    if (data) {
      this.estimateSendMode = data.estimateSendMode || "";
    } else if (error) {
      this.estimateSendMode = "";
    }
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

  handleCancel() {
    this.dispatchEvent(new CloseActionScreenEvent());
  }

  // 仕様: Core 第4.3.1節
  handleSelect(event) {
    const key = event.currentTarget?.dataset?.key;
    const url = this.urlForSelectedAction(key);
    if (!url) {
      return;
    }
    this.dispatchEvent(new CloseActionScreenEvent());
    this.scheduleOpenSelectedAction(url);
  }

  urlForSelectedAction(key) {
    if (!key || !this.recordId) {
      return "";
    }
    if (key === "issue") {
      return `/apex/EstimateDocumentIssue?id=${encodeURIComponent(this.recordId)}`;
    }
    const apiName = QUICK_ACTIONS[key];
    if (!apiName) {
      return "";
    }
    return `/lightning/action/quick/${apiName}?recordId=${encodeURIComponent(this.recordId)}`;
  }

  scheduleOpenSelectedAction(url) {
    if (!url || typeof window === "undefined") {
      return;
    }
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    window.setTimeout(() => {
      window.location.href = url;
    }, 0);
  }
}
