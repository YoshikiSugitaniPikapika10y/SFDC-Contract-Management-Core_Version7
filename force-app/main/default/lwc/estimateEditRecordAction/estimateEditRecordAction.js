import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { getRecord } from "lightning/uiRecordApi";
import hasEditEstimate from "@salesforce/customPermission/Loop_03_Can_Estimate";
import HISTORY_STATUS_FIELD from "@salesforce/schema/ContractHistory__c.historystatus__c";
import {
  closeEstimateWizard,
  markEstimateRecordForRefresh,
  refreshOnEstimateRecordActionUnmount
} from "c/estimateWizardClose";
import { resizeQuickActionPanel } from "c/quickActionPanelResize";

export default class EstimateEditRecordAction extends NavigationMixin(
  LightningElement
) {
  @api recordId;

  pendingRecordRefresh;
  historyStatus;

  get hasPermission() {
    return hasEditEstimate === true;
  }

  // 仕様: Core 第4.3節、第4.3.1節
  get canOpenWizard() {
    return this.hasPermission && Boolean(this.historyStatus);
  }

  @wire(getRecord, { recordId: "$recordId", fields: [HISTORY_STATUS_FIELD] })
  wiredHistory({ data, error }) {
    if (data) {
      this.historyStatus = data.fields?.historystatus__c?.value || "";
    } else if (error) {
      this.historyStatus = "";
    }
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
