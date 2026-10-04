import { LightningElement, api } from "lwc";
import { CloseActionScreenEvent } from "lightning/actions";
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

  /** 仕様: Core 第4.3.1節・第5.5節。子の閉じるを受け、Quick Action 本体がパネルを閉じる。 */
  handleRequestClose() {
    this.dispatchEvent(new CloseActionScreenEvent());
  }
}
