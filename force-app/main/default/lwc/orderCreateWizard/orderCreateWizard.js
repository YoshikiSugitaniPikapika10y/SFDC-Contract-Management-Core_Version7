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
import confirmOrder from "@salesforce/apex/OrderCreateController.confirmOrder";

const HISTORY_TYPE_CANCEL = "Cancel";

export default class OrderCreateWizard extends NavigationMixin(
  LightningElement
) {
  _recordId;

  @api
  get recordId() {
    return this._recordId;
  }
  set recordId(value) {
    this._recordId = value;
  }

  @track isTabView = false;
  @track isLoading = true;
  @track isSaving = false;
  @track errorMessage = "";
  @track context;
  @track billingCustomFields = {};
  @track createRenewOpportunity = true;
  /** 楽観ロック（getOrderContext.lastModifiedToken） */
  _lastModifiedToken = "";

  connectedCallback() {
    initializeOrderWizardFromUrl(this);
    // 開くたびに最新コンテキストを取り直す（同一 recordId の再利用キャッシュを捨てる）
    resetRecordActionLoadState(this);
    scheduleRecordActionLoad(this, () => this.loadContext());
    this.emitPanelSize();
  }

  renderedCallback() {
    scheduleRecordActionLoad(this, () => this.loadContext());
  }

  @wire(CurrentPageReference)
  setCurrentPageReference(pageRef) {
    const recordId = readOrderWizardRecordId(pageRef);
    if (recordId) {
      this._recordId = recordId;
    }
    this.isTabView = isOrderWizardTabView(pageRef, "order");
  }

  get pageClass() {
    return this.isTabView ? "ord-page ord-page_tab" : "ord-page ord-page_modal";
  }

  get cancelPageClass() {
    return this.isTabView
      ? "confirm-page cancel-page cancel-page_tab"
      : "confirm-page cancel-page cancel-page_modal";
  }

  async loadContext() {
    if (!this.recordId) {
      return;
    }

    this.isLoading = true;
    this.errorMessage = "";
    this.context = undefined;
    this.emitPanelSize();

    try {
      const data = await getOrderContext({
        contractHistoryId: this.recordId
      });

      if (data.historyStatus === HISTORY_STATUS_ARCHIVE) {
        this.errorMessage =
          "アーカイブ済みの契約履歴では受注は利用できません。";
        return;
      }

      if (data.isOrdered) {
        this.errorMessage =
          "受注済みの契約履歴です。「請求プレビュー」「差し戻し」ボタンをご利用ください。";
        return;
      }

      this.context = data;
      this._lastModifiedToken = data.lastModifiedToken || "";
      this.billingCustomFields = { ...(data.billingCustomFields || {}) };
      // 表示時は常に初期 ON（ユーザが意図的に外さない限り作成／作り直し）
      this.createRenewOpportunity = true;
      // 請求ステップの wire／LDS もコンテキスト確定後に最新化
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      Promise.resolve().then(() => {
        this.template
          .querySelector("c-order-create-step-billing")
          ?.refreshReferenceWires?.();
      });
    } catch (error) {
      this.errorMessage = this.reduceError(error);
    } finally {
      this.isLoading = false;
      this.emitPanelSize();
    }
  }

  get hasContext() {
    return !!this.context;
  }

  get isCancel() {
    return this.context?.historyType === HISTORY_TYPE_CANCEL;
  }

  get isCancelConfirm() {
    return this.hasContext && this.isCancel;
  }

  get showBillingStep() {
    return this.hasContext && !this.isCancel;
  }

  get showMissingRecordError() {
    return !this.recordId && this._recordActionMissingHandled;
  }

  get showBootstrapLoading() {
    return isOrderActionBootstrapping(this);
  }

  get canOrder() {
    return this.context?.canOrder === true;
  }

  get showCreateRenewOpportunity() {
    return this.context?.showCreateRenewOpportunity === true;
  }

  get hasBillingAccount() {
    return Boolean(this.context?.billingAccountId);
  }

  handleCreateRenewOpportunityChange(event) {
    this.createRenewOpportunity = event.target.checked === true;
  }

  get isBusy() {
    return this.isLoading || this.isSaving;
  }

  get isOrderDisabled() {
    return this.isBusy || !this.canOrder;
  }

  get panelSize() {
    return this.isCancelConfirm ? "confirm" : "large";
  }

  emitPanelSize() {
    this.dispatchEvent(
      new CustomEvent("panelsizechange", {
        bubbles: true,
        composed: true,
        detail: { size: this.panelSize }
      })
    );
  }

  validateBillingStep() {
    const billingStep = this.template.querySelector(
      "c-order-create-step-billing"
    );
    if (
      billingStep &&
      typeof billingStep.validateBillingFields === "function"
    ) {
      return billingStep.validateBillingFields();
    }
    return null;
  }

  async handleConfirmOrder() {
    if (this.isSaving || !this.canOrder) {
      return;
    }
    if (!this.hasBillingAccount) {
      this.errorMessage =
        "請求アカウントが未設定のため受注できません。見積で請求アカウントを設定してください。";
      return;
    }

    this.isSaving = true;
    this.errorMessage = "";
    try {
      if (!this.isCancel) {
        const validationError = this.validateBillingStep();
        if (validationError) {
          this.errorMessage = validationError;
          this.showToast("入力エラー", validationError, "error");
          this.isSaving = false;
          return;
        }
      }
      const shouldCreateRenew =
        this.showCreateRenewOpportunity && this.createRenewOpportunity;
      const result = await confirmOrder({
        contractHistoryId: this.recordId,
        billingCustomFieldsJson: null,
        createRenewOpportunity: shouldCreateRenew,
        expectedLastModifiedToken: this._lastModifiedToken || null
      });
      notifyOrderRecordStatusChanged(this, this.recordId);
      const renewCreated = Boolean(result?.renewOpportunityId);
      this.showToast(
        "受注完了",
        renewCreated
          ? "ステータスを Ordered に更新し、更新商談を作成しました。"
          : "ステータスを Ordered に更新しました。",
        "success"
      );
      this.closeAction();
    } catch (error) {
      this.errorMessage = this.reduceError(error);
      this.showToast("受注エラー", this.errorMessage, "error");
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

  showToast(title, message, variant) {
    this.dispatchEvent(
      new ShowToastEvent({
        title,
        message,
        variant
      })
    );
  }

  reduceError(error) {
    const alert = resolveSaveErrorAlert(error);
    return alert.messages.map((entry) => entry.text).join("\n");
  }
}
