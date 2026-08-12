import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { CloseActionScreenEvent } from "lightning/actions";
import { RefreshEvent } from "lightning/refresh";
import { getRecordNotifyChange } from "lightning/uiRecordApi";
import archiveEstimate from "@salesforce/apex/EstimateArchiveController.archiveEstimate";
import hasArchiveEstimate from "@salesforce/customPermission/Contract_07_Can_Archive_Estimate";
import { resolveSaveErrorAlert } from "c/estimateValidationAlertUtils";
import { resizeQuickActionPanel } from "c/quickActionPanelResize";

export default class EstimateArchiveRecordAction extends LightningElement {
  @api recordId;

  isWorking = false;
  errorMessage = "";

  connectedCallback() {
    resizeQuickActionPanel(this, "confirm");
  }

  renderedCallback() {
    resizeQuickActionPanel(this, "confirm");
  }

  get hasPermission() {
    return hasArchiveEstimate === true;
  }

  get isBusy() {
    return this.isWorking;
  }

  get isArchiveDisabled() {
    return this.isBusy || !this.recordId || !this.hasPermission;
  }

  handleCancel() {
    this.closeAction(false);
  }

  async handleArchive() {
    if (this.isArchiveDisabled) {
      return;
    }

    this.isWorking = true;
    this.errorMessage = "";
    try {
      await archiveEstimate({ contractHistoryId: this.recordId });
      this.dispatchEvent(
        new ShowToastEvent({
          title: "アーカイブ完了",
          message: "ステータスを Archive に更新しました。",
          variant: "success"
        })
      );
      this.closeAction(true);
    } catch (error) {
      const alert = resolveSaveErrorAlert(error);
      this.errorMessage = alert.messages.map((entry) => entry.text).join("\n");
      this.dispatchEvent(
        new ShowToastEvent({
          title: "アーカイブエラー",
          message: this.errorMessage,
          variant: "error",
          mode: "sticky"
        })
      );
    } finally {
      this.isWorking = false;
    }
  }

  closeAction(refresh) {
    if (refresh && this.recordId) {
      getRecordNotifyChange([{ recordId: this.recordId }]);
      this.dispatchEvent(new RefreshEvent());
    }
    this.dispatchEvent(new CloseActionScreenEvent());
  }
}
