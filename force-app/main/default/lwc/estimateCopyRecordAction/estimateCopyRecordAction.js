import { LightningElement, api } from "lwc";
import hasCopyEstimate from "@salesforce/customPermission/Loop_03_Can_Estimate";
import {
  closeEstimateWizard,
  markEstimateRecordForRefresh,
  refreshOnEstimateRecordActionUnmount
} from "c/estimateWizardClose";
import { resizeQuickActionPanel } from "c/quickActionPanelResize";

export default class EstimateCopyRecordAction extends LightningElement {
  _recordId = "";

  pendingRecordRefresh;

  // 仕様: Core 第4.3.1節、第4.7節。Quick Action の recordId は後から入ることがある。空ではウィザードを開かない。
  @api
  get recordId() {
    return this._recordId;
  }
  set recordId(value) {
    this._recordId = value || "";
  }

  get hasCopySourceId() {
    return Boolean(this._recordId);
  }

  get hasPermission() {
    return hasCopyEstimate === true;
  }

  connectedCallback() {
    resizeQuickActionPanel(this);
  }

  renderedCallback() {
    resizeQuickActionPanel(this);
  }

  // 仕様: Core 第4.3.2節・第4.3.6節
  handleRequestClose(event) {
    const detail = event.detail || {};
    closeEstimateWizard(this, {
      refresh: detail.refresh !== false,
      opportunityId: detail.opportunityId,
      contractHistoryId: detail.contractHistoryId || this.recordId,
      navigateToContractHistoryId: detail.navigateToContractHistoryId
    });
  }

  handleEstimateSaved(event) {
    markEstimateRecordForRefresh(
      this,
      event.detail?.opportunityId || event.detail?.contractHistoryId
    );
  }

  disconnectedCallback() {
    refreshOnEstimateRecordActionUnmount(this);
  }
}
