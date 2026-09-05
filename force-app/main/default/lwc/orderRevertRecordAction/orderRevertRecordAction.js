import { LightningElement, api } from "lwc";
import { NavigationMixin } from "c/orderWizardNavigation";
import hasRevert from "@salesforce/customPermission/Loop_07_Can_Revert";
import {
  closeOrderRecordAction,
  markOrderRecordForRefresh,
  refreshOnRecordActionUnmount
} from "c/orderWizardClose";
import { resizeQuickActionPanel } from "c/quickActionPanelResize";

export default class OrderRevertRecordAction extends NavigationMixin(
  LightningElement
) {
  @api recordId;

  pendingRecordRefresh;

  get hasPermission() {
    return hasRevert === true;
  }

  // 仕様: Core 第4.3.1節、第5.3節。差し戻しは Archive・ハブと同型の小さい confirm。
  connectedCallback() {
    resizeQuickActionPanel(this, "confirm");
  }

  renderedCallback() {
    resizeQuickActionPanel(this, "confirm");
  }

  handleRequestClose(event) {
    const detail = event.detail || {};
    closeOrderRecordAction(this, {
      refresh: detail.refresh !== false,
      recordId: detail.recordId || this.recordId
    });
  }

  handleOrderRecordStatusChanged(event) {
    markOrderRecordForRefresh(this, event.detail?.recordId);
  }

  disconnectedCallback() {
    refreshOnRecordActionUnmount(this);
  }
}
