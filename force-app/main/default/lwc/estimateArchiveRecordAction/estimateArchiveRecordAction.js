import { LightningElement, api } from "lwc";
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
  _recordId = "";
  _contextRequestSeq = 0;

  isWorking = false;
  errorMessage = "";
  historyStatus = "";

  /** 仕様: Core 第0.1節、第4.3.1節、第5.5節。Archive＝不採用。破棄ではない。 */
  get confirmSubtitle() {
    return "見積を不採用にして編集不可にします";
  }
  _lastModifiedToken = "";
  _pendingOperationKey = "";

  // 仕様: Core 第4.3.1節、第5.5節。Quick Action の recordId は後から入ることがある。
  @api
  get recordId() {
    return this._recordId;
  }
  set recordId(value) {
    const next = value || "";
    if (next === this._recordId) {
      return;
    }
    this._recordId = next;
    this.loadContext();
  }

  connectedCallback() {
    resizeQuickActionPanel(this, "confirm");
    this.loadContext();
  }

  renderedCallback() {
    resizeQuickActionPanel(this, "confirm");
  }

  // 仕様: Core 第5.5節、第4.3.11節。開いた契約履歴の状態をサーバから取る。
  async loadContext() {
    const historyId = this._recordId;
    if (!historyId) {
      return;
    }
    this._contextRequestSeq += 1;
    const requestSeq = this._contextRequestSeq;
    try {
      const context = await getArchiveContext({
        contractHistoryId: historyId
      });
      if (requestSeq !== this._contextRequestSeq || this._recordId !== historyId) {
        return;
      }
      this._lastModifiedToken = context?.lastModifiedToken || "";
      this.historyStatus = context?.historyStatus || "";
      this.errorMessage =
        this.historyStatus && this.historyStatus !== STATUS_ESTIMATE
          ? NON_ESTIMATE_ARCHIVE_MESSAGE
          : "";
    } catch (error) {
      if (requestSeq !== this._contextRequestSeq || this._recordId !== historyId) {
        return;
      }
      const alert = resolveSaveErrorAlert(error);
      this.errorMessage = alert.messages.map((entry) => entry.text).join("\n");
    }
  }

  handleReloadContext() {
    this.errorMessage = "";
    return this.loadContext();
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
      this.closeAction(true);
    } catch (error) {
      const alert = resolveSaveErrorAlert(error);
      this.errorMessage = alert.messages.map((entry) => entry.text).join("\n");
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
