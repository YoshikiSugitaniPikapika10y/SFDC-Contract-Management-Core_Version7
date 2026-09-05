import { LightningElement, api } from "lwc";
import hasCopyEstimate from "@salesforce/customPermission/Loop_03_Can_Estimate";
import {
  closeEstimateWizard,
  markEstimateRecordForRefresh,
  refreshOnEstimateRecordActionUnmount
} from "c/estimateWizardClose";
import { resizeQuickActionPanel } from "c/quickActionPanelResize";

export default class EstimateCopyRecordAction extends LightningElement {
  @api recordId;

  pendingRecordRefresh;

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
