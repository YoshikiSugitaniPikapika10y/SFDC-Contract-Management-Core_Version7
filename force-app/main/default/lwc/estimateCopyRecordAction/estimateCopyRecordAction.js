import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import hasCopyEstimate from "@salesforce/customPermission/Contract_06_Can_Copy_Estimate";
import {
  closeEstimateWizard,
  markEstimateRecordForRefresh,
  refreshOnEstimateRecordActionUnmount
} from "c/estimateWizardClose";
import { resizeQuickActionPanel } from "c/quickActionPanelResize";

export default class EstimateCopyRecordAction extends NavigationMixin(
  LightningElement
) {
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

  handleRequestClose(event) {
    const detail = event.detail || {};
    closeEstimateWizard(this, {
      refresh: detail.refresh !== false,
      opportunityId: detail.opportunityId,
      contractHistoryId: detail.contractHistoryId || this.recordId
    });

    const navigateToId = detail.navigateToContractHistoryId;
    if (navigateToId) {
      this[NavigationMixin.Navigate]({
        type: "standard__recordPage",
        attributes: {
          recordId: navigateToId,
          objectApiName: "ContractHistory__c",
          actionName: "view"
        }
      });
    }
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
