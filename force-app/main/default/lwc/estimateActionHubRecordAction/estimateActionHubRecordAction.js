import { LightningElement, api } from "lwc";
import { resizeQuickActionPanel } from "c/quickActionPanelResize";

/** 仕様: Core 第4.3.1節 */
export default class EstimateActionHubRecordAction extends LightningElement {
  @api recordId;

  connectedCallback() {
    resizeQuickActionPanel(this, "confirm");
  }

  renderedCallback() {
    resizeQuickActionPanel(this, "confirm");
  }
}
