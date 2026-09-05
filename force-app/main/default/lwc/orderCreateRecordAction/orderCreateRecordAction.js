import { LightningElement, api } from "lwc";
import { NavigationMixin } from "c/orderWizardNavigation";
import hasOrder from "@salesforce/customPermission/Loop_06_Can_Order";
import {
  closeOrderRecordAction,
  markOrderRecordForRefresh,
  refreshOnRecordActionUnmount
} from "c/orderWizardClose";
import { resizeQuickActionPanel } from "c/quickActionPanelResize";

export default class OrderCreateRecordAction extends NavigationMixin(
  LightningElement
) {
  _recordId = "";

  // 仕様: Core 第5.2節。Quick Action の recordId は後から入ることがある。
  @api
  get recordId() {
    return this._recordId;
  }
  set recordId(value) {
    this._recordId = value || "";
  }

  pendingRecordRefresh;
  panelSize = "large";

  get hasPermission() {
    return hasOrder === true;
  }

  connectedCallback() {
    this.applyPanelSize();
  }

  renderedCallback() {
    this.applyPanelSize();
  }

  handlePanelSizeChange(event) {
    const size = event.detail?.size;
    if (size !== "confirm" && size !== "large") {
      return;
    }
    if (this.panelSize === size) {
      return;
    }
    this.panelSize = size;
    this.applyPanelSize();
  }

  applyPanelSize() {
    resizeQuickActionPanel(this, this.panelSize);
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
