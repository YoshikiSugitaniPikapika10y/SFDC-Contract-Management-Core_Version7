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
import hasRevert from "@salesforce/customPermission/Loop_07_Can_Revert";
import getOrderContext from "@salesforce/apex/OrderCreateController.getOrderContext";
import revertOrder from "@salesforce/apex/OrderCreateController.revertOrder";
import issueOrderOperationKey from "@salesforce/apex/OrderCreateController.issueOrderOperationKey";
import hasManualInvoiceAdjustment from "@salesforce/apex/OrderCreateController.hasManualInvoiceAdjustment";
import { buildCustomFieldInputs } from "c/estimateWizardCustomFields";

const VERSION_CONFLICT_MESSAGE =
  "他のユーザーが先に更新しました。画面を開き直してから再度操作してください。";

export default class OrderRevertWizard extends NavigationMixin(
  LightningElement
) {
  @api recordId;

  pendingRecordRefresh;

  @track isTabView = false;
  @track isLoading = true;
  @track isSaving = false;
  @track errorMessage = "";
  @track contentLoadFailed = false;
  @track context;
  @track hasManualAdjustment = false;
  @track deleteRenewOpportunity = true;
  @track historyCustomFields = {};
  /** 楽観ロック（getOrderContext.lastModifiedToken） */
  _lastModifiedToken = "";
  /** 仕様: Core 第4.3.12節 */
  _pendingOperationKey = "";

  get canOpenRevert() {
    return hasRevert === true;
  }

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
    this.contentLoadFailed = false;
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
          "見積状態の契約履歴です。「受注」ボタンをご利用ください。";
        return;
      }

      this.context = data;
      this._lastModifiedToken = data.lastModifiedToken || "";
      this.historyCustomFields = { ...(data.historySavedFields || {}) };
      delete this.historyCustomFields.OrderDate__c;
      // 表示時は常に初期 ON（ユーザが意図的に外さない限り削除）
      this.deleteRenewOpportunity = true;
      this.hasManualAdjustment = await hasManualInvoiceAdjustment({
        contractHistoryId: this.recordId
      });
    } catch (error) {
      // 仕様: Core 第4.3.11節
      this.errorMessage = this.reduceError(error);
      this.contentLoadFailed = true;
    } finally {
      this.isLoading = false;
    }
  }

  /** 仕様: Core 第4.3.11節 */
  handleContentReload() {
    this.loadContext();
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

  // 仕様: Core 第5.3節、第11.4.3節
  get revertHistoryFieldDefinitions() {
    return (this.context?.historyFieldDefinitions || [])
      .filter((field) => field && field.apiName !== "OrderDate__c")
      .map((field) => ({
        ...field,
        required: false
      }));
  }

  get historyFieldInputs() {
    return buildCustomFieldInputs(
      this.revertHistoryFieldDefinitions,
      this.historyCustomFields,
      "revert-history",
      false,
      null,
      this.context?.historyType
    );
  }

  get showHistoryFields() {
    return this.canRevert && this.historyFieldInputs.length > 0;
  }

  handleHistoryFieldChange(event) {
    const fieldApi = event.detail?.fieldApi;
    if (!fieldApi || fieldApi === "OrderDate__c") {
      return;
    }
    this.historyCustomFields = {
      ...this.historyCustomFields,
      [fieldApi]: event.detail.value
    };
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
      if (!this._pendingOperationKey) {
        this._pendingOperationKey = await issueOrderOperationKey();
      }
      const result = await revertOrder({
        contractHistoryId: this.recordId,
        deleteRenewOpportunity: shouldDeleteRenew,
        expectedLastModifiedToken: this._lastModifiedToken || null,
        historyCustomFieldsJson: JSON.stringify(this.historyCustomFields || {}),
        businessOperationKey: this._pendingOperationKey
      });
      if (result?.businessOperationKey) {
        this._pendingOperationKey = result.businessOperationKey;
      }
      this._pendingOperationKey = "";
      notifyOrderRecordStatusChanged(this, this.recordId);
      this.showToast(
        "差し戻し完了",
        shouldDeleteRenew
          ? "ステータスを見積に戻し、更新商談を削除しました。"
          : "ステータスを見積に戻しました。",
        "success"
      );
      this.closeAction();
    } catch (error) {
      this.errorMessage = this.reduceError(error);
      this.showToast("差し戻しエラー", this.errorMessage, "error", "sticky");
      // 仕様: Core 第4.3.12節。版比較失敗時は画面を読み直す。
      if (this.errorMessage === VERSION_CONFLICT_MESSAGE) {
        this._pendingOperationKey = "";
        await this.loadContext();
      }
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
