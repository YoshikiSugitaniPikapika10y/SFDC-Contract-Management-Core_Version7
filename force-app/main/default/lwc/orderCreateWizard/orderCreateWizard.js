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
import issueOrderOperationKey from "@salesforce/apex/OrderCreateController.issueOrderOperationKey";
import {
  applyDefaultCustomFields,
  buildCustomFieldInputs,
  isMissingRequiredCustomValue
} from "c/estimateWizardCustomFields";
import hasOrder from "@salesforce/customPermission/Loop_06_Can_Order";

const HISTORY_TYPE_CANCEL = "Cancel";

const VERSION_CONFLICT_MESSAGE =
  "他のユーザーが先に更新しました。画面を開き直してから再度操作してください。";

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
  @track contentLoadFailed = false;
  @track context;
  @track billingCustomFields = {};
  @track historyCustomFields = {};
  @track historyFieldDefinitions = [];
  @track createRenewOpportunity = true;
  /** 楽観ロック（getOrderContext.lastModifiedToken） */
  _lastModifiedToken = "";
  /** 仕様: Core 第4.3.12節 */
  _pendingOperationKey = "";

  get canOrder() {
    return hasOrder === true;
  }

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
    this.contentLoadFailed = false;
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
          "受注済みの契約履歴です。「請求ボード」「差し戻し」ボタンをご利用ください。";
        return;
      }

      this.context = data;
      this._lastModifiedToken = data.lastModifiedToken || "";
      this.historyFieldDefinitions = data.historyFieldDefinitions || [];
      this.historyCustomFields = applyDefaultCustomFields(
        { ...(data.historyCustomFields || {}) },
        this.historyFieldDefinitions,
        null,
        data.historyType,
        null
      );
      this.billingCustomFields = { ...(data.billingCustomFields || {}) };
      // 仕様: Core 第5.2節、第11.5節。TermのNew・Change・Renewは初期状態ON。
      this.createRenewOpportunity = data.showCreateRenewOpportunity === true;
      // 請求ステップの wire／LDS もコンテキスト確定後に最新化
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      Promise.resolve().then(() => {
        this.template
          .querySelector("c-order-create-step-billing")
          ?.refreshReferenceWires?.();
      });
    } catch (error) {
      // 仕様: Core 第4.3.11節
      this.errorMessage = this.reduceError(error);
      this.contentLoadFailed = true;
    } finally {
      this.isLoading = false;
      this.emitPanelSize();
    }
  }

  /** 仕様: Core 第4.3.11節 */
  handleContentReload() {
    this.loadContext();
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

  get historyFieldInputs() {
    return buildCustomFieldInputs(
      this.historyFieldDefinitions,
      this.historyCustomFields,
      "order-history",
      false,
      null,
      this.context?.historyType
    );
  }

  get showHistoryFields() {
    return this.historyFieldInputs.length > 0;
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

  handleHistoryFieldChange(event) {
    const fieldApi = event.detail?.fieldApi;
    if (!fieldApi) {
      return;
    }
    this.historyCustomFields = {
      ...this.historyCustomFields,
      [fieldApi]: event.detail.value
    };
  }

  validateHistoryFields() {
    const missingLabels = [];
    for (const field of this.historyFieldInputs) {
      if (field.required !== true) {
        continue;
      }
      if (
        isMissingRequiredCustomValue(this.historyCustomFields[field.apiName])
      ) {
        missingLabels.push(field.label);
      }
    }
    if (missingLabels.length === 0) {
      return null;
    }
    return "必須のカスタム項目を入力してください: " + missingLabels.join("、");
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

  /** 仕様: Core 第5.2節。必須不足時は請求アカウントの正規編集画面へ誘導する。 */
  guideToBillingAccountFormalEdit() {
    const billingStep = this.template.querySelector(
      "c-order-create-step-billing"
    );
    if (
      billingStep &&
      typeof billingStep.openBillingAccountFormalEdit === "function"
    ) {
      billingStep.openBillingAccountFormalEdit();
    }
  }

  // 仕様: Core 第5.2節、第1.1.10節。Cancelも請求アカウント必須検証を維持し、不足は正規編集へ誘導する。
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
      const historyError = this.validateHistoryFields();
      if (historyError) {
        this.errorMessage = historyError;
        this.showToast("入力エラー", historyError, "error");
        this.isSaving = false;
        return;
      }
      const validationError = this.validateBillingStep();
      if (validationError) {
        this.errorMessage = validationError;
        this.showToast("入力エラー", validationError, "error");
        this.guideToBillingAccountFormalEdit();
        this.isSaving = false;
        return;
      }
      const shouldCreateRenew =
        this.showCreateRenewOpportunity && this.createRenewOpportunity;
      if (!this._pendingOperationKey) {
        this._pendingOperationKey = await issueOrderOperationKey();
      }
      const result = await confirmOrder({
        contractHistoryId: this.recordId,
        billingCustomFieldsJson: null,
        createRenewOpportunity: shouldCreateRenew,
        expectedLastModifiedToken: this._lastModifiedToken || null,
        historyCustomFieldsJson: JSON.stringify(this.historyCustomFields || {}),
        businessOperationKey: this._pendingOperationKey
      });
      if (result?.businessOperationKey) {
        this._pendingOperationKey = result.businessOperationKey;
      }
      this._pendingOperationKey = "";
      notifyOrderRecordStatusChanged(this, this.recordId);
      const renewCreated = Boolean(result?.renewOpportunityId);
      this.showToast(
        "受注完了",
        renewCreated
          ? "ステータスを受注済みに更新し、更新商談を作成しました。"
          : "ステータスを受注済みに更新しました。",
        "success"
      );
      this.closeAction();
    } catch (error) {
      this.errorMessage = this.reduceError(error);
      this.showToast("受注エラー", this.errorMessage, "error");
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
    this.dispatchEvent(
      new CustomEvent("panelclose", { bubbles: true, composed: true })
    );
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
