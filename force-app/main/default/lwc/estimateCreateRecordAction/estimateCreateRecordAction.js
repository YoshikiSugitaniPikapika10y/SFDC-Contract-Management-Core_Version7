import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import hasCreateEstimate from "@salesforce/customPermission/Contract_04_Can_Create_Estimate";
import {
  closeEstimateWizard,
  markEstimateRecordForRefresh,
  refreshOnEstimateRecordActionUnmount
} from "c/estimateWizardClose";
import { resizeQuickActionPanel } from "c/quickActionPanelResize";

export default class EstimateCreateRecordAction extends NavigationMixin(
  LightningElement
) {
  @api recordId;

  pendingRecordRefresh;

  get hasPermission() {
    return hasCreateEstimate === true;
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
      opportunityId: detail.opportunityId || this.recordId,
      contractHistoryId: detail.contractHistoryId
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
      event.detail?.opportunityId || this.recordId
    );
  }

  disconnectedCallback() {
    refreshOnEstimateRecordActionUnmount(this);
  }
}
