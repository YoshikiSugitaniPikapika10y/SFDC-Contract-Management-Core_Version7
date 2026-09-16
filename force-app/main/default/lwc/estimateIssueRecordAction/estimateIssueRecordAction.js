import { LightningElement, api } from "lwc";
import { CloseActionScreenEvent } from "lightning/actions";

/** 仕様: Core 第4.3.1節・第4.8節・第7.10節。既存の見積書発行面をレコードQuick Action内に保つ。 */
export default class EstimateIssueRecordAction extends LightningElement {
  @api recordId;

  get issuePageUrl() {
    return this.recordId
      ? `/apex/EstimateDocumentIssue?id=${encodeURIComponent(this.recordId)}`
      : "";
  }

  handleClose() {
    this.dispatchEvent(new CloseActionScreenEvent());
  }
}
