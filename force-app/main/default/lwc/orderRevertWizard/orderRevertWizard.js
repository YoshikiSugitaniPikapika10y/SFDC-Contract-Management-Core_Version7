import { LightningElement, api, track, wire } from "lwc";
import { CurrentPageReference } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { resolveSaveErrorAlert } from "c/estimateValidationAlertUtils";
import {
  closeOrderWizardTab,
  initializeOrderWizardFromUrl,
  isOrderWizardTabView,
  NavigationMixin,
  readOrderWizardRecordId
} from "c/orderWizardNavigation";
import {
  HISTORY_STATUS_ARCHIVE,
  isOrderActionBootstrapping,
  notifyOrderRecordStatusChanged,
  requestOrderWizardClose,
  scheduleRecordActionLoad,
  resetRecordActionLoadState
} from "c/orderWizardClose";
import getOrderContext from "@salesforce/apex/OrderCreateController.getOrderContext";
import revertOrder from "@salesforce/apex/OrderCreateController.revertOrder";
import hasManualInvoiceAdjustment from "@salesforce/apex/OrderCreateController.hasManualInvoiceAdjustment";

export default class OrderRevertWizard extends NavigationMixin(
  LightningElement
) {
  @api recordId;

  pendingRecordRefresh;

  @track isTabView = false;
  @track isLoading = true;
  @track isSaving = false;
  @track errorMessage = "";
  @track context;
  @track hasManualAdjustment = false;
  @track deleteRenewOpportunity = true;
  /** 楽観ロック（getOrderContext.lastModifiedToken） */
  _lastModifiedToken = "";

  connectedCallback() {
    initializeOrderWizardFromUrl(this);
    // 開くたびに差し戻し判定・コンテキストをサーバ最新で取り直す
    resetRecordActionLoadState(this);
    scheduleRecordActionLoad(this, () => this.loadContext());
  }

  renderedCallback() {
    scheduleRecordActionLoad(this, () => this.loadContext());
  }

  @wire(CurrentPageReference)
  setCurrentPageReference(pageRef) {
    const recordId = readOrderWizardRecordId(pageRef);
    if (recordId) {
      // eslint-disable-next-line @lwc/lwc/no-api-reassignments
      this.recordId = recordId;
    }
    this.isTabView = isOrderWizardTabView(pageRef, "revert");
  }

  get pageClass() {
    return this.isTabView
      ? "confirm-page revert-page revert-page_tab"
      : "confirm-page revert-page revert-page_modal";
  }

  async loadContext() {
    if (!this.recordId) {
      return;
    }

    this.isLoading = true;
    this.errorMessage = "";
    this.context = undefined;

    try {
      const data = await getOrderContext({
        contractHistoryId: this.recordId
      });

      if (data.historyStatus === HISTORY_STATUS_ARCHIVE) {
        this.errorMessage =
          "アーカイブ済みの契約履歴では差し戻しは利用できません。";
        return;
      }

      if (!data.isOrdered) {
        this.errorMessage =
          "Estimate 状態の契約履歴です。「受注」ボタンをご利用ください。";
        return;
      }

      this.context = data;
      this._lastModifiedToken = data.lastModifiedToken || "";
      // 表示時は常に初期 ON（ユーザが意図的に外さない限り削除）
      this.deleteRenewOpportunity = true;
      this.hasManualAdjustment = await hasManualInvoiceAdjustment({
        contractHistoryId: this.recordId
      });
    } catch (error) {
      this.errorMessage = this.reduceError(error);
    } finally {
      this.isLoading = false;
    }
  }

  get canRevert() {
    return this.context?.canRevert === true;
  }

  get hasRenewOpportunity() {
    return this.context?.hasRenewOpportunity === true;
  }

  handleDeleteRenewOpportunityChange(event) {
    this.deleteRenewOpportunity = event.target.checked === true;
  }

  get revertBlockedReason() {
    return this.context?.revertBlockedReason || "";
  }

  get showRevertBlockedNotice() {
    return Boolean(this.revertBlockedReason);
  }

  get hasContext() {
    return !!this.context;
  }

  get showBootstrapLoading() {
    return isOrderActionBootstrapping(this);
  }

  get showManualAdjustmentNotice() {
    return this.canRevert && this.hasManualAdjustment;
  }

  get isBusy() {
    return this.isLoading || this.isSaving;
  }

  get isRevertDisabled() {
    return this.isBusy || !this.canRevert;
  }

  async handleRevert() {
    if (this.isSaving || !this.canRevert) {
      return;
    }
    this.isSaving = true;
    this.errorMessage = "";
    try {
      const shouldDeleteRenew =
        this.hasRenewOpportunity && this.deleteRenewOpportunity;
      await revertOrder({
        contractHistoryId: this.recordId,
        deleteRenewOpportunity: shouldDeleteRenew,
        expectedLastModifiedToken: this._lastModifiedToken || null
      });
      notifyOrderRecordStatusChanged(this, this.recordId);
      this.showToast(
        "差し戻し完了",
        shouldDeleteRenew
          ? "ステータスを Estimate に戻し、更新商談を削除しました。"
          : "ステータスを Estimate に戻しました。",
        "success"
      );
      this.closeAction();
    } catch (error) {
      this.errorMessage = this.reduceError(error);
      this.showToast("差し戻しエラー", this.errorMessage, "error", "sticky");
    } finally {
      this.isSaving = false;
    }
  }

  handleClose() {
    this.closeAction({ refresh: false });
  }

  closeAction({ refresh = true } = {}) {
    if (this.isTabView) {
      closeOrderWizardTab(this, {
        recordId: this.recordId,
        refresh
      });
      return;
    }
    requestOrderWizardClose(this, { refresh, recordId: this.recordId });
  }

  showToast(title, message, variant, mode) {
    this.dispatchEvent(
      new ShowToastEvent({
        title,
        message,
        variant,
        mode
      })
    );
  }

  reduceError(error) {
    const alert = resolveSaveErrorAlert(error);
    return alert.messages.map((entry) => entry.text).join("\n");
  }
}
