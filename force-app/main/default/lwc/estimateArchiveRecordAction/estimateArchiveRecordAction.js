import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { CloseActionScreenEvent } from "lightning/actions";
import { RefreshEvent } from "lightning/refresh";
import { getRecordNotifyChange } from "lightning/uiRecordApi";
import archiveEstimate from "@salesforce/apex/EstimateArchiveController.archiveEstimate";
import getArchiveContext from "@salesforce/apex/EstimateArchiveController.getArchiveContext";
import issueEstimateOperationKey from "@salesforce/apex/EstimateCreateController.issueEstimateOperationKey";
import hasArchiveEstimate from "@salesforce/customPermission/Loop_03_Can_Estimate";
import { resolveSaveErrorAlert } from "c/estimateValidationAlertUtils";
import { resizeQuickActionPanel } from "c/quickActionPanelResize";

const VERSION_CONFLICT_MESSAGE =
  "他のユーザーが先に更新しました。画面を開き直してから再度操作してください。";
const STATUS_ESTIMATE = "Estimate";
const NON_ESTIMATE_ARCHIVE_MESSAGE =
  "見積状態の契約履歴のみ不採用にできます。";

export default class EstimateArchiveRecordAction extends LightningElement {
  @api recordId;

  isWorking = false;
  errorMessage = "";
  historyStatus = "";

  /** 仕様: Core 第0.1節、第4.3.1節、第5.5節。Archive＝不採用。破棄ではない。 */
  get confirmSubtitle() {
    return "見積を不採用にして編集不可にします";
  }
  _lastModifiedToken = "";
  _pendingOperationKey = "";

  connectedCallback() {
    resizeQuickActionPanel(this, "confirm");
    this.loadContext();
  }

  renderedCallback() {
    resizeQuickActionPanel(this, "confirm");
  }

  async loadContext() {
    if (!this.recordId) {
      return;
    }
    try {
      const context = await getArchiveContext({
        contractHistoryId: this.recordId
      });
      this._lastModifiedToken = context?.lastModifiedToken || "";
      this.historyStatus = context?.historyStatus || "";
      if (this.historyStatus && this.historyStatus !== STATUS_ESTIMATE) {
        this.errorMessage = NON_ESTIMATE_ARCHIVE_MESSAGE;
      }
    } catch (error) {
      const alert = resolveSaveErrorAlert(error);
      this.errorMessage = alert.messages.map((entry) => entry.text).join("\n");
    }
  }

  get hasPermission() {
    return hasArchiveEstimate === true;
  }

  get isBusy() {
    return this.isWorking;
  }

  get isEstimate() {
    return this.historyStatus === STATUS_ESTIMATE;
  }

  /** 仕様: Core 第5.5節、第1.1.10節。手動ArchiveはEstimateだけ。 */
  get isArchiveDisabled() {
    return this.isBusy || !this.recordId || !this.hasPermission || !this.isEstimate;
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
      if (!this._pendingOperationKey) {
        this._pendingOperationKey = await issueEstimateOperationKey();
      }
      const result = await archiveEstimate({
        contractHistoryId: this.recordId,
        expectedLastModifiedToken: this._lastModifiedToken || null,
        businessOperationKey: this._pendingOperationKey
      });
      if (result?.businessOperationKey) {
        this._pendingOperationKey = result.businessOperationKey;
      }
      this._pendingOperationKey = "";
      this.dispatchEvent(
        new ShowToastEvent({
          title: "アーカイブ完了",
          message: "ステータスを不採用に更新しました。",
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
      // 仕様: Core 第4.3.12節。版比較失敗時は画面を読み直す。
      if (this.errorMessage === VERSION_CONFLICT_MESSAGE) {
        this._pendingOperationKey = "";
        await this.loadContext();
      }
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
