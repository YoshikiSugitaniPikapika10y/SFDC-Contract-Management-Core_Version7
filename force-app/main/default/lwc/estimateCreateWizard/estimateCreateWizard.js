import { LightningElement, api, track, wire } from "lwc";
import { CurrentPageReference } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { getRecordNotifyChange } from "lightning/uiRecordApi";
import { refreshApex } from "@salesforce/apex";
import saveEstimate from "@salesforce/apex/EstimateCreateController.saveEstimate";
import issueEstimateOperationKey from "@salesforce/apex/EstimateCreateController.issueEstimateOperationKey";
import getDocumentDefaults from "@salesforce/apex/EstimateCreateController.getDocumentDefaults";
import getEstimateCopyPreset from "@salesforce/apex/EstimateCreateController.getEstimateCopyPreset";
import getEstimateEditPreset from "@salesforce/apex/EstimateCreateController.getEstimateEditPreset";
import getLatestContractHistory from "@salesforce/apex/EstimateCreateController.getLatestContractHistory";
import getContractServiceFieldDefinitions from "@salesforce/apex/ContractWizardFieldService.getContractServiceFieldDefinitions";
import getContractHistoryFieldDefinitions from "@salesforce/apex/ContractWizardFieldService.getContractHistoryFieldDefinitions";
import getContractProductFieldDefinitions from "@salesforce/apex/ContractWizardFieldService.getContractProductFieldDefinitions";
import getOpportunityDefaultContext from "@salesforce/apex/ContractWizardFieldService.getOpportunityDefaultContext";
import getOrderHistoryFieldDefinitions from "@salesforce/apex/OrderWizardFieldService.getDefinitions";
import {
  validateBillingPeriod,
  validateNewProducts,
  validateSpotChangeProducts,
  validateNewEffectiveDate,
  validateRenewProducts,
  validateRenewEffectiveDate,
  validateCancelProducts,
  validateCancelEffectiveDate,
  validateChangeProducts,
  validateChangeEffectiveDate,
  validateChangePeriodDates,
  buildChangeSameProductNewConfirmMessage,
  isValidIsoDate,
  validateAmountEntryUnitPrices,
  isChangeOriginalLine,
  productTypeDisplayLabel
} from "c/estimateLineItemUtils";
import {
  buildWizardValidationAlert,
  buildConfirmValidationAlert,
  resolveSaveErrorAlert
} from "c/estimateValidationAlertUtils";
import { requestEstimateWizardClose } from "c/estimateWizardClose";
import { validateCustomFieldMaps } from "c/estimateWizardCustomFields";
import hasEstimate from "@salesforce/customPermission/Loop_03_Can_Estimate";
import {
  WIZARD_ACTIONS,
  createInitialWizardState,
  reduceWizardState,
  buildPresetKey,
  canLeaveCurrentStep,
  shouldLoadPreset,
  applyEstimateDocumentDefaults
} from "c/estimateWizardState";

export default class EstimateCreateWizard extends LightningElement {
  @api recordId;
  @api modalMode = false;

  _skipSameProductNewConfirm = false;
  /**
   * 確認ダイアログは同時に1種類だけ。
   * null | { kind: 'close' } | { kind: 'remarks', requestId } | { kind: 'sameProductNew' }
   */
  _confirmState = null;
  /** 保存クリックの同期ガード（isSaving 再描画前の二重実行防止） */
  _saveInFlight = false;
  /** 仕様: Core 第4.3.12節。押下時発行。応答前の連打は別キーにしないよう保持する */
  _pendingOperationKey = "";
  /** このセッション中に保存が成功したか（未保存で閉じる際の確認表示に使用） */
  _saveSucceededThisSession = false;
  _wizardInitialized = false;
  _wiredServiceFieldDefinitions;
  _wiredHistoryFieldDefinitions;
  _wiredProductFieldDefinitions;
  _wiredOpportunityDefaultContext;
  /** オープン時に子パネルを作り直すためのセッションキー */
  _contentSessionSeq = 0;

  serviceFieldDefinitions = [];
  historyFieldDefinitions = [];
  orderHistoryFieldDefinitions = [];
  productFieldDefinitions = [];
  opportunityDefaultContext = {};
  /**
   * 契約特定パネル（modal2）の remount 用。開くたび／種別変更で更新する。
   * LWC は key 付き for:each で子を破棄・再生成できる。
   */
  @track contractPanelSessionItems = ["p-0"];
  /** EstimateWizardField__mdt 不正時の設定エラー（保存不可） */
  @track wizardFieldConfigError = "";
  /**
   * getOpportunityDefaultContext 用。getter は wire の $ に使えないため同期する。
   * 空文字は Id 型として無効になり wire が失敗するため、未確定時は undefined のままにする。
   */
  @track opportunityIdForContext;

  /**
   * コピー元 / 編集元 ID の唯一のソース。
   * 優先順位: @api → pageRef → URL（空のときだけ下位ソースで埋める）。
   */
  @track copyFromHistoryId = "";
  @track editHistoryId = "";

  @api
  get copySourceHistoryId() {
    return this.copyFromHistoryId;
  }
  set copySourceHistoryId(value) {
    const next = value || "";
    if (next === this.copyFromHistoryId) {
      return;
    }
    this.copyFromHistoryId = next;
    if (next && this.showWizard) {
      this.ensurePresetLoaded();
    }
  }

  @api
  get editSourceHistoryId() {
    return this.editHistoryId;
  }
  set editSourceHistoryId(value) {
    const next = value || "";
    if (next === this.editHistoryId) {
      return;
    }
    this.editHistoryId = next;
    if (next && this.showWizard) {
      this.ensurePresetLoaded();
    }
  }

  @track validationAlert = null;
  @track opportunityRecordId = "";
  @track isTabView = false;

  /**
   * ウィザードの唯一の状態。書き換えは dispatch() 経由のみで行う。
   * 直接のプロパティ代入やスプレッドマージは禁止。
   */
  @track wizardState = createInitialWizardState();

  dispatch(action) {
    this.wizardState = reduceWizardState(this.wizardState, action);
  }

  get wizardData() {
    return this.wizardState.data;
  }

  get currentStep() {
    return this.wizardState.step;
  }

  /** 入口（new/continuation）確定後、または編集時に契約特定パネルを出す */
  get showContractIdentifyPanel() {
    if (this.isEditMode || this.isOrderedCustomFieldsOnlyEdit) {
      return true;
    }
    const mode = this.wizardData?.entryMode || "";
    return mode === "new" || mode === "continuation";
  }

  get isStep2Mounted() {
    return this.wizardState.ui.step2Mounted;
  }

  get isStep3Mounted() {
    return this.wizardState.ui.step3Mounted;
  }

  get isSaving() {
    return (
      this.wizardState.async.saving === true || this._saveInFlight === true
    );
  }

  get isLoadingCopy() {
    return this.wizardState.async.loadingPreset;
  }

  get copyLoadError() {
    return this.wizardState.async.presetError;
  }

  get loadingContractHistory() {
    return this.wizardState.async.loadingContractHistory;
  }

  get loadingStep3() {
    return this.wizardState.async.loadingStep3 === true;
  }

  /** Step2 表示中でも裏で明細が更新されるため、常に告知する */
  get showStep3SyncBanner() {
    return this.loadingStep3;
  }

  get step3SyncBannerMessage() {
    return "商品明細を更新しています。完了するまで「次へ」「保存」はできません。表示内容が確定したあと、その内容が保存されます。";
  }

  get showContractHistoryLoadingBanner() {
    return this.loadingContractHistory === true;
  }

  @wire(CurrentPageReference)
  setCurrentPageReference(pageRef) {
    if (pageRef?.state?.c__recordId) {
      this.opportunityRecordId = pageRef.state.c__recordId;
    }
    // @api で既に入っている値を pageRef で上書きしない。
    if (pageRef?.state?.c__copyFromHistoryId && !this.copyFromHistoryId) {
      this.copyFromHistoryId = pageRef.state.c__copyFromHistoryId;
    }
    if (pageRef?.state?.c__editHistoryId && !this.editHistoryId) {
      this.editHistoryId = pageRef.state.c__editHistoryId;
    }
    const componentName = pageRef?.attributes?.componentName || "";
    const apiName = pageRef?.attributes?.apiName || "";
    this.isTabView =
      apiName === "Estimate_Create" ||
      pageRef?.type === "standard__navItemPage" ||
      pageRef?.type === "standard__namedPage" ||
      (pageRef?.type === "standard__component" &&
        componentName.includes("estimateCreateWizard"));
  }

  @wire(getContractServiceFieldDefinitions)
  wiredServiceFieldDefinitions(result) {
    this._wiredServiceFieldDefinitions = result;
    const { data, error } = result;
    if (data) {
      this.serviceFieldDefinitions = data;
    } else if (error) {
      this.wizardFieldConfigError = this.resolveApexErrorMessage(error);
    }
  }

  @wire(getContractHistoryFieldDefinitions)
  wiredHistoryFieldDefinitions(result) {
    this._wiredHistoryFieldDefinitions = result;
    const { data, error } = result;
    if (data) {
      this.historyFieldDefinitions = data;
    } else if (error) {
      this.wizardFieldConfigError = this.resolveApexErrorMessage(error);
    }
  }

  @wire(getContractProductFieldDefinitions)
  wiredProductFieldDefinitions(result) {
    this._wiredProductFieldDefinitions = result;
    const { data, error } = result;
    if (data) {
      this.productFieldDefinitions = data;
    } else if (error) {
      this.wizardFieldConfigError = this.resolveApexErrorMessage(error);
    }
  }

  @wire(getOpportunityDefaultContext, {
    opportunityId: "$opportunityIdForContext"
  })
  wiredOpportunityDefaultContext(result) {
    this._wiredOpportunityDefaultContext = result;
    const { data, error } = result;
    // 編集・コピーは契約履歴IDだけで起動し、商談IDはプリセット後に入る。
    // 未設定時の wire エラー（空文字 Id など）は設定エラーとして扱わない。
    if (!this.opportunityIdForContext) {
      this.opportunityDefaultContext = {};
      return;
    }
    if (error) {
      this.wizardFieldConfigError = this.resolveApexErrorMessage(error);
      this.opportunityDefaultContext = {};
      return;
    }
    this.opportunityDefaultContext = data || {};
  }

  resolveApexErrorMessage(error) {
    return (
      error?.body?.message ||
      error?.message ||
      "見積ウィザードのカスタム項目設定が不正です。カスタムメタデータを確認してください。"
    );
  }

  syncOpportunityIdForContext() {
    const next = this.effectiveRecordId || undefined;
    if (this.opportunityIdForContext !== next) {
      this.opportunityIdForContext = next;
    }
  }

  get isEditMode() {
    return Boolean(this.editHistoryId);
  }

  get isOrderedCustomFieldsOnlyEdit() {
    return (
      this.isEditMode &&
      String(this.wizardData?.historyStatus || "").toLowerCase() === "ordered"
    );
  }

  // 仕様: Core 第4.3節、第4.3.1節
  get displayedHistoryFieldDefinitions() {
    if (!this.isOrderedCustomFieldsOnlyEdit) {
      return this.historyFieldDefinitions;
    }
    return [
      ...(this.historyFieldDefinitions || []),
      ...(this.orderHistoryFieldDefinitions || [])
    ];
  }

  get showWizard() {
    return this.isTabView || this.modalMode;
  }

  get pageClass() {
    const classes = ["est-page"];
    if (this.modalMode) {
      classes.push("est-page_modal");
    }
    // Edit/Copy の preset 読込中は本文入力をロック（完了時の無言上書きを防ぐ）
    if (this.isLoadingCopy) {
      classes.push("est-page_preset-loading");
    }
    return classes.join(" ");
  }

  get showMissingRecordError() {
    return (
      !this.isLoadingCopy &&
      !this.effectiveRecordId &&
      !this.copyFromHistoryId &&
      !this.editHistoryId
    );
  }

  get effectiveRecordId() {
    if (this.opportunityRecordId) {
      return this.opportunityRecordId;
    }
    if (this.copyFromHistoryId || this.editHistoryId) {
      return "";
    }
    return this.recordId || "";
  }

  get isStep1() {
    return this.currentStep === 1;
  }
  get isStep2() {
    return this.currentStep === 2;
  }

  get canSaveEstimate() {
    return hasEstimate === true;
  }
  /** @deprecated 2段階構成では詳細情報＝Step2。保存ボタン表示用に残す。 */
  get isStep3() {
    return this.currentStep === 2;
  }
  get isNextDisabled() {
    return (
      !canLeaveCurrentStep(this.wizardState) ||
      !this.effectiveRecordId ||
      this.hasOpenConfirm ||
      this.isSaving
    );
  }

  get isPrevDisabled() {
    return this.isSaving || this.hasOpenConfirm;
  }

  get hasOpenConfirm() {
    return this._confirmState != null;
  }

  get hasValidationAlert() {
    return (
      this.validationAlert &&
      this.validationAlert.messages &&
      this.validationAlert.messages.length > 0
    );
  }

  get validationAlertVariant() {
    return (this.validationAlert && this.validationAlert.variant) || "error";
  }

  get validationAlertShowActions() {
    return Boolean(this.validationAlert && this.validationAlert.showActions);
  }

  get headerTitle() {
    return this.isEditMode ? "見積編集" : "見積作成";
  }

  get typeLabel() {
    const labels = {
      New: "新規",
      Change: "追加変更",
      Renew: "更新",
      Cancel: "解約"
    };
    const value = this.wizardData.selectedType || "New";
    return labels[value] || value;
  }

  get step1PanelClass() {
    return this.currentStep === 1
      ? "est-step-panel"
      : "est-step-panel est-step-panel_hidden";
  }

  get step2PanelClass() {
    // 基本情報内の契約特定パネル（modal2）も Step1 で表示する
    return this.currentStep === 1
      ? "est-step-panel"
      : "est-step-panel est-step-panel_hidden";
  }

  get step3PanelClass() {
    // 詳細情報（旧 Step3 / modal3）＝ナビ上の Step2
    return this.currentStep === 2
      ? "est-step-panel"
      : "est-step-panel est-step-panel_hidden";
  }

  get isStep1PanelAriaHidden() {
    return this.currentStep !== 1;
  }

  get isStep2PanelAriaHidden() {
    return this.currentStep !== 1;
  }

  get isStep3PanelAriaHidden() {
    return this.currentStep !== 2;
  }

  /**
   * Step3 画面上の明細・期間を親 wizardData へ強制同期する。
   * 保存直前に呼び、表示と保存ペイロードのズレを防ぐ。
   * @returns {boolean} 同期できた（読込中でない / 未マウント）とき true
   */
  flushStep3ToParent() {
    const modal3 = this.template.querySelector(
      '[data-id="estimate-create-modal3"]'
    );
    if (!modal3 || typeof modal3.flushToParent !== "function") {
      return true;
    }
    return modal3.flushToParent() !== false;
  }

  /** flush 失敗時の案内。金額ポップアップ未確定を優先して明示する。 */
  getStep3FlushBlockMessage(actionLabel) {
    const action = actionLabel || "続行";
    const modal3 = this.template.querySelector(
      '[data-id="estimate-create-modal3"]'
    );
    if (modal3 && modal3.hasOpenAmountModal === true) {
      return `金額の入力を適用（またはキャンセル）してから${action}してください。非整数の式は整数円に直して適用が必要です。`;
    }
    return `商品明細を更新中です。完了してから${action}してください。`;
  }

  handleSaveClick() {
    if (this._saveInFlight || this.wizardState.async.saving) {
      return;
    }
    if (!this.effectiveRecordId) {
      this.showValidationAlert("商談IDが指定されていません。");
      return;
    }
    if (this.hasOpenConfirm) {
      this.showToast(
        "確認中です",
        "確認ダイアログに回答してから保存してください。",
        "info"
      );
      return;
    }
    if (!canLeaveCurrentStep(this.wizardState)) {
      if (this.loadingStep3) {
        this.showValidationAlert(
          "商品明細を更新中です。完了してから保存してください。"
        );
      }
      return;
    }
    // 再描画前の二重クリックを同期で止める（確認ダイアログ前はまだ立てない）
    // flush の changefield が handleStep3Change でフラグを落とすため、先に退避する。
    const skipSameProductConfirm = this._skipSameProductNewConfirm;
    if (!this.flushStep3ToParent()) {
      this.showValidationAlert(this.getStep3FlushBlockMessage("保存"));
      return;
    }
    const productsForConfirm = this.wizardData.selectedProducts || [];

    if (this.wizardData.selectedType === "Change" && !skipSameProductConfirm) {
      const sameProductNewMessage =
        buildChangeSameProductNewConfirmMessage(productsForConfirm);
      if (sameProductNewMessage) {
        this.openConfirm({ kind: "sameProductNew" }, sameProductNewMessage);
        return;
      }
    }
    this._skipSameProductNewConfirm = false;

    const detailError = this.validateStep2();
    if (detailError) {
      this.showValidationAlert(detailError);
      return;
    }
    this._saveInFlight = true;
    this.handleSave();
  }

  handleConfirmRequest(event) {
    const detail = event.detail || {};
    const requestId = detail.requestId || null;
    if (this.hasOpenConfirm) {
      // 既存確認を優先。新しい備考確認は拒否して Promise を閉じる。
      this.resolveModal3Confirm(requestId, false);
      this.showToast(
        "確認中です",
        "先に表示中の確認に回答してください。",
        "info"
      );
      return;
    }
    this.openConfirm({ kind: "remarks", requestId }, detail.message || "");
  }

  handleConfirmationProceed() {
    const state = this._confirmState;
    if (!state) {
      this.clearValidationAlert();
      return;
    }
    this._confirmState = null;
    this.clearValidationAlert();
    if (state.kind === "close") {
      this.performClose();
      return;
    }
    if (state.kind === "remarks") {
      this.resolveModal3Confirm(state.requestId, true);
      return;
    }
    if (state.kind === "sameProductNew") {
      this._skipSameProductNewConfirm = true;
      // 同商品新規の確認後は、画面に出ている明細で保存を続行する
      this.handleSaveClick();
    }
  }

  handleConfirmationCancel() {
    const state = this._confirmState;
    if (!state) {
      this.clearValidationAlert();
      return;
    }
    this._confirmState = null;
    this.clearValidationAlert();
    if (state.kind === "remarks") {
      this.resolveModal3Confirm(state.requestId, false);
      return;
    }
    if (state.kind === "sameProductNew") {
      this._skipSameProductNewConfirm = false;
    }
  }

  /** 確認を1件だけ開く。既存がある場合は false（呼び出し側で拒否処理）。 */
  openConfirm(state, message) {
    if (this.hasOpenConfirm) {
      return false;
    }
    this._confirmState = state;
    this.showConfirmationAlert(message);
    return true;
  }

  resolveModal3Confirm(requestId, confirmed) {
    if (!requestId) {
      return;
    }
    const modal3 = this.template.querySelector(
      '[data-id="estimate-create-modal3"]'
    );
    if (modal3 && typeof modal3.resolveConfirmRequest === "function") {
      modal3.resolveConfirmRequest(requestId, confirmed);
    }
  }

  /** 開いている確認をキャンセル扱いして閉じる（別確認へ切り替える前に使う）。 */
  dismissOpenConfirm() {
    const state = this._confirmState;
    if (!state) {
      return;
    }
    this._confirmState = null;
    this.clearValidationAlert();
    if (state.kind === "remarks") {
      this.resolveModal3Confirm(state.requestId, false);
    }
    if (state.kind === "sameProductNew") {
      this._skipSameProductNewConfirm = false;
    }
  }

  get stepItems() {
    const labels = ["基本情報", "詳細情報"];
    return labels.map((label, index) => {
      const num = index + 1;
      const isCurrent = this.currentStep === num;
      const canGoBack = num < this.currentStep;
      const canGoForward = this.canNavigateForwardTo(num);
      const isClickable =
        !this.isSaving &&
        !this.hasOpenConfirm &&
        !isCurrent &&
        (canGoBack || canGoForward);

      let itemClass = "est-step";
      if (isCurrent) {
        itemClass += " est-step_active";
      } else if (this.currentStep > num) {
        itemClass += " est-step_done";
      } else if (!canGoForward) {
        itemClass += " est-step_locked";
      }
      if (isClickable) {
        itemClass += " est-step_clickable";
      }

      return {
        key: `step-${num}`,
        num,
        label,
        itemClass,
        isCurrent,
        isClickable,
        ariaCurrent: isCurrent ? "step" : null,
        showConnector: num < 2,
        connectorClass:
          this.currentStep > num
            ? "est-step-connector est-step-connector_done"
            : "est-step-connector"
      };
    });
  }

  canNavigateForwardTo(targetStep) {
    if (!canLeaveCurrentStep(this.wizardState)) {
      return false;
    }
    if (targetStep <= this.currentStep) {
      return true;
    }
    if (targetStep >= 2 && this.validateStep1()) {
      return false;
    }
    return true;
  }

  /** Change / Renew / Cancel で継続課金の期間整合がないときの共通メッセージ。 */
  renewEligibleFalseMessage(selectedType) {
    const labels = {
      Change: "追加変更",
      Renew: "更新",
      Cancel: "解約"
    };
    const typeLabel = labels[selectedType] || selectedType;
    return (
      "前回の版の期間終了日と一致する継続課金商品がありません。" +
      typeLabel +
      "できません。新規で作成してください。"
    );
  }

  /**
   * Step1 で Change / Renew / Cancel を選んだあと、通常画面では起きない
   * 不整合（期末到達の継続課金明細が無い）だけをすぐ出す。カードは隠さない。
   */
  maybeShowIneligibleOperationAlert() {
    const d = this.wizardData;
    const type = d && d.selectedType;
    if (type !== "Change" && type !== "Renew" && type !== "Cancel") {
      // New へ切替えたあとに Change 不可メッセージが残らないようにする
      this.clearValidationAlert();
      return;
    }
    if (d.serviceLifecycle === "Spot") {
      if (type === "Renew" || type === "Cancel") {
        this.showValidationAlert(
          "都度契約では更新／解約は使えません。一回課金だけの追加変更を使ってください。"
        );
      } else {
        this.clearValidationAlert();
      }
      return;
    }
    if (d.renewEligible === false) {
      this.showValidationAlert(this.renewEligibleFalseMessage(type));
      return;
    }
    if (d.renewEligible === true) {
      this.clearValidationAlert();
    }
  }

  connectedCallback() {
    this.initializeFromUrl();
    // 開いた瞬間に状態・子パネル・参照 wire を最新化する（クライアントキャッシュの取り残し防止）
    this.beginFreshContentSession();
  }

  /**
   * ウィザード表示内容を「今開いた時点の最新」に揃える。
   * - ウィザード状態を初期化（preset 再読込可）
   * - 契約特定パネルを remount（ローカル候補状態のクリア）
   * - CMDT／商談コンテキスト wire と LDS を再取得
   */
  beginFreshContentSession() {
    this._contentSessionSeq += 1;
    this.contractPanelSessionItems = [`p-${this._contentSessionSeq}`];
    this._saveSucceededThisSession = false;
    this._saveInFlight = false;
    this._confirmState = null;
    this._skipSameProductNewConfirm = false;
    this.validationAlert = null;
    this.wizardState = createInitialWizardState();
    this._wizardInitialized = false;
    this.loadDocumentDefaults();
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    Promise.resolve().then(() => {
      this.refreshWizardReferenceWires();
    });
  }

  remountContractPanel() {
    this._contentSessionSeq += 1;
    this.contractPanelSessionItems = [`p-${this._contentSessionSeq}`];
  }

  refreshWizardReferenceWires() {
    const jobs = [];
    if (this._wiredServiceFieldDefinitions) {
      jobs.push(refreshApex(this._wiredServiceFieldDefinitions));
    }
    if (this._wiredHistoryFieldDefinitions) {
      jobs.push(refreshApex(this._wiredHistoryFieldDefinitions));
    }
    if (this._wiredProductFieldDefinitions) {
      jobs.push(refreshApex(this._wiredProductFieldDefinitions));
    }
    if (this._wiredOpportunityDefaultContext && this.opportunityIdForContext) {
      jobs.push(refreshApex(this._wiredOpportunityDefaultContext));
    }
    if (this.effectiveRecordId) {
      getRecordNotifyChange([{ recordId: this.effectiveRecordId }]);
    }
    return Promise.all(jobs);
  }

  initializeFromUrl() {
    if (typeof window === "undefined") {
      return;
    }

    const href = window.location.href;
    const isWizardUrl =
      href.includes("/lightning/cmp/c__estimateCreateWizard") ||
      href.includes("/lightning/n/Estimate_Create");

    if (isWizardUrl) {
      this.isTabView = true;
    }

    try {
      const url = new URL(href);
      const recordId = url.searchParams.get("c__recordId");
      if (recordId) {
        this.opportunityRecordId = recordId;
      }
      // @api / pageRef より後に走らないよう、空のときだけ埋める。
      const copyFromHistoryId = url.searchParams.get("c__copyFromHistoryId");
      if (copyFromHistoryId && !this.copyFromHistoryId) {
        this.copyFromHistoryId = copyFromHistoryId;
      }
      const editHistoryId = url.searchParams.get("c__editHistoryId");
      if (editHistoryId && !this.editHistoryId) {
        this.editHistoryId = editHistoryId;
      }
    } catch {
      // URL解析失敗時は wire に任せる
    }
  }

  renderedCallback() {
    this.syncOpportunityIdForContext();

    if (!this.showWizard) {
      return;
    }

    if (this.editHistoryId || this.copyFromHistoryId) {
      this.ensurePresetLoaded();
      return;
    }

    if (!this._wizardInitialized) {
      this._wizardInitialized = true;
      this.dispatch({ type: WIZARD_ACTIONS.INITIALIZE_NEW });
      this.loadDocumentDefaults();
    }
  }

  loadDocumentDefaults() {
    const session = this._contentSessionSeq;
    this._documentDefaultsRequestSeq = (this._documentDefaultsRequestSeq || 0) + 1;
    const requestSeq = this._documentDefaultsRequestSeq;
    this.wizardState = {
      ...this.wizardState,
      async: { ...this.wizardState.async, loadingDocumentDefaults: true }
    };
    getDocumentDefaults()
      .then((defaults) => {
        if (
          session !== this._contentSessionSeq ||
          requestSeq !== this._documentDefaultsRequestSeq
        ) {
          return;
        }
        this._documentDefaults = defaults;
        this.wizardState = applyEstimateDocumentDefaults(
          {
            ...this.wizardState,
            async: {
              ...this.wizardState.async,
              loadingDocumentDefaults: false
            }
          },
          defaults
        );
      })
      .catch((error) => {
        if (
          session !== this._contentSessionSeq ||
          requestSeq !== this._documentDefaultsRequestSeq
        ) {
          return;
        }
        this.wizardState = {
          ...this.wizardState,
          async: { ...this.wizardState.async, loadingDocumentDefaults: false }
        };
        const message =
          (error && error.body && error.body.message) ||
          error.message ||
          "契約帳票・送付設定を読めませんでした。";
        this.showToast("エラー", message, "error");
      });
  }

  reapplyDocumentDefaultsFromCache() {
    if (!this._documentDefaults) {
      return;
    }
    this.wizardState = applyEstimateDocumentDefaults(
      this.wizardState,
      this._documentDefaults
    );
  }

  ensurePresetLoaded() {
    if (this.editHistoryId) {
      if (
        shouldLoadPreset(
          this.wizardState,
          buildPresetKey(this.editHistoryId, "edit")
        )
      ) {
        this.loadPreset(this.editHistoryId, true);
      }
      return;
    }

    if (!this.copyFromHistoryId) {
      return;
    }
    if (
      shouldLoadPreset(
        this.wizardState,
        buildPresetKey(this.copyFromHistoryId, "copy")
      )
    ) {
      this.loadPreset(this.copyFromHistoryId, false);
    }
  }

  handlePresetRetry() {
    const sourceId = this.editHistoryId || this.copyFromHistoryId;
    if (!sourceId) {
      return;
    }
    this.dispatch({ type: WIZARD_ACTIONS.PRESET_CLEAR_FAILURE });
    this.loadPreset(sourceId, !!this.editHistoryId);
  }

  async loadPreset(sourceId, forEdit) {
    if (!sourceId) {
      return;
    }

    const key = buildPresetKey(sourceId, forEdit ? "edit" : "copy");
    const session = this._contentSessionSeq;
    this.dispatch({ type: WIZARD_ACTIONS.PRESET_LOAD_START, key });
    try {
      const preset = forEdit
        ? await getEstimateEditPreset({ contractHistoryId: sourceId })
        : await getEstimateCopyPreset({ contractHistoryId: sourceId });
      // オープン時のセッション初期化より前に始まった読込は捨てる
      if (session !== this._contentSessionSeq) {
        return;
      }
      if (preset?.opportunityId) {
        this.opportunityRecordId = preset.opportunityId;
        this.syncOpportunityIdForContext();
      }
      this.dispatch({
        type: WIZARD_ACTIONS.PRESET_LOAD_SUCCESS,
        preset,
        key
      });
      this.clearValidationAlert();
      await this.loadOrderHistoryFieldDefinitions(preset);
    } catch (error) {
      if (session !== this._contentSessionSeq) {
        return;
      }
      const message =
        error?.body?.message ||
        error?.message ||
        (forEdit
          ? "見積編集内容の読み込みに失敗しました。"
          : "見積コピーの読み込みに失敗しました。");
      this.dispatch({
        type: WIZARD_ACTIONS.PRESET_LOAD_FAILURE,
        key,
        message
      });
    }
  }

  async loadOrderHistoryFieldDefinitions(preset) {
    const isOrdered =
      String(preset?.historyStatus || "").toLowerCase() === "ordered";
    if (!isOrdered) {
      this.orderHistoryFieldDefinitions = [];
      return;
    }
    try {
      this.orderHistoryFieldDefinitions = await getOrderHistoryFieldDefinitions({
        wizardType: preset.selectedType || ""
      });
    } catch (error) {
      this.orderHistoryFieldDefinitions = [];
      this.wizardFieldConfigError = this.resolveApexErrorMessage(error);
    }
  }

  setCurrentStep(step) {
    this.dispatch({ type: WIZARD_ACTIONS.SET_STEP, step });
  }

  getLightningBase() {
    const href = window.location.href;
    const lightningIndex = href.indexOf("/lightning/");
    return lightningIndex >= 0
      ? href.substring(0, lightningIndex)
      : window.location.origin;
  }

  handleStep1EntryChange(event) {
    if (this.isEditMode) {
      return;
    }
    this.clearValidationAlert();
    this.dispatch({
      type: WIZARD_ACTIONS.SET_ENTRY_MODE,
      entryMode: event.detail?.entryMode
    });
    this.remountContractPanel();
  }

  handleStep1TypeChange(event) {
    // 編集時はタイプを変更できない。
    if (this.isEditMode) {
      return;
    }
    const previousType = this.wizardData.selectedType || "";
    const hadService = Boolean(this.wizardData.contractServiceId);
    const nextType = event.detail?.selectedType;
    this.clearValidationAlert();
    this.dispatch({
      type: WIZARD_ACTIONS.SET_TYPE,
      selectedType: nextType
    });
    // 仕様: Core 第4.3節、第4.3.7節。種別を変えたら契約選択を作り直す。
    // サービス選択後の初回操作選択（"" → Change 等）だけパネルを維持する。
    const typeChanged = previousType !== (nextType || "");
    const keepContinuationFirstSelect =
      previousType === "" && hadService && nextType !== "New";
    if (typeChanged && !keepContinuationFirstSelect) {
      this.remountContractPanel();
    }
    this.maybeShowIneligibleOperationAlert();
    this.reapplyDocumentDefaultsFromCache();
  }

  handleOpportunityLoaded(event) {
    const detail = event.detail || {};
    this.dispatch({
      type: WIZARD_ACTIONS.SET_OPPORTUNITY,
      opportunityName: detail.opportunityName,
      accountName: detail.accountName,
      opportunityContactId: detail.opportunityContactId
    });
  }

  handleStep2Change(event) {
    this.clearValidationAlert();
    this.dispatch({
      type: WIZARD_ACTIONS.MERGE_STEP2,
      fields: event.detail || {}
    });
  }

  /**
   * 契約サービスの選択に伴う契約履歴の取得。
   * 選択時点で依存項目を破棄し、連番の一致する応答だけを採用する。
   */
  async handleContractServiceSelect(event) {
    const detail = event.detail || {};
    const contractServiceId = detail.contractServiceId || "";
    const contractServiceName = (detail.contractServiceName || "").trim();
    const serviceLifecycle = detail.serviceLifecycle || "";
    this.dispatch({
      type: WIZARD_ACTIONS.SELECT_CONTRACT_SERVICE_START,
      serviceLifecycle,
      contractServiceId,
      contractServiceName
    });
    if (!contractServiceId) {
      return;
    }

    const requestId = this.wizardState.async.serviceRequestId;
    try {
      const result = await getLatestContractHistory({ contractServiceId });
      this.dispatch({
        type: WIZARD_ACTIONS.SELECT_CONTRACT_SERVICE_SUCCESS,
        requestId,
        result
      });
      this.maybeShowIneligibleOperationAlert();
      this.reapplyDocumentDefaultsFromCache();
    } catch {
      this.dispatch({
        type: WIZARD_ACTIONS.SELECT_CONTRACT_SERVICE_FAILURE,
        requestId
      });
      this.showValidationAlert("契約履歴の取得に失敗しました。");
    }
  }

  handleStep3Loading(event) {
    this.dispatch({
      type: WIZARD_ACTIONS.SET_STEP3_LOADING,
      loading: (event.detail || {}).loading === true
    });
  }

  handleStep3Change(event) {
    // Step3 は CSS 非表示中でもブートストラップ完了を親へ書き通す必要がある。
    // （Step2 で契約を切り替えたあと、非表示の Step3 が新明細を読み込む）
    this._skipSameProductNewConfirm = false;
    // 詳細画面表示中の編集だけアラートを消す（裏 bootstrap で操作不可アラートを消さない）
    if (this.currentStep === 2) {
      this.clearValidationAlert();
    }
    this.dispatch({
      type: WIZARD_ACTIONS.MERGE_STEP3,
      fields: event.detail || {}
    });
  }

  handleStepClick(event) {
    if (this.isSaving || this.hasOpenConfirm) {
      return;
    }

    const targetStep = Number(event.currentTarget.dataset.step);
    if (!targetStep || targetStep === this.currentStep) {
      return;
    }

    if (targetStep < this.currentStep) {
      if (this.currentStep === 2 && !this.flushStep3ToParent()) {
        this.showValidationAlert(this.getStep3FlushBlockMessage("戻る"));
        return;
      }
      this.clearValidationAlert();
      this.setCurrentStep(targetStep);
      return;
    }

    const step1Error = this.validateStep1();
    if (step1Error) {
      this.showValidationAlert(step1Error);
      return;
    }

    this.clearValidationAlert();
    this.setCurrentStep(targetStep);
  }

  handlePrev() {
    if (this.isSaving || this.hasOpenConfirm) {
      return;
    }
    if (this.currentStep === 2) {
      if (!this.flushStep3ToParent()) {
        this.showValidationAlert(this.getStep3FlushBlockMessage("戻る"));
        return;
      }
    }
    this.clearValidationAlert();
    if (this.currentStep === 2) {
      this.setCurrentStep(1);
    }
  }

  handleNext() {
    if (!this.effectiveRecordId) {
      this.showValidationAlert("商談IDが指定されていません。");
      return;
    }
    if (this.hasOpenConfirm) {
      this.showToast(
        "確認中です",
        "確認ダイアログに回答してから進んでください。",
        "info"
      );
      return;
    }
    if (!canLeaveCurrentStep(this.wizardState)) {
      if (this.loadingStep3) {
        this.showValidationAlert(
          "商品明細を更新中です。完了してから次へ進んでください。"
        );
      } else if (this.loadingContractHistory) {
        this.showValidationAlert(
          "契約履歴を読み込み中です。完了してから次へ進んでください。"
        );
      } else if (this.wizardState.async.loadingDocumentDefaults) {
        this.showValidationAlert(
          "見積書の初期値を読み込み中です。完了してから次へ進んでください。"
        );
      }
      return;
    }

    if (this.currentStep === 1) {
      const step1Error = this.validateStep1();
      if (step1Error) {
        this.showValidationAlert(step1Error);
        return;
      }
      this.clearValidationAlert();
      this.setCurrentStep(2);
    }
  }

  /** 仕様: Core 第4.3.4節、第4.6節 */
  validateTaxPercent(taxPercent) {
    if (taxPercent === "" || taxPercent == null) {
      return "消費税率を入力してください。空欄は0%になりません。";
    }
    const numeric = Number(taxPercent);
    if (!Number.isFinite(numeric)) {
      return "消費税率が不正です。";
    }
    if (numeric < 0) {
      return "消費税率が不正です（負の値は指定できません）。";
    }
    if (numeric > 0 && numeric < 1) {
      return "消費税率は0〜100のパーセント値で入力してください。";
    }
    if (numeric > 100) {
      return "消費税率が不正です（100を超える値は指定できません）。";
    }
    return null;
  }

  /**
   * 仕様: Core 第4.3.3節、第3.2節、第3.4節、第1.1.8節、第1.1.10節。
   * 未設定の請求アカウントは見積保存しない。取引先の無い商談は画面で止める。
   * Step1（基本情報）: タイプと契約の特定。追加項目は見ない。
   */
  validateStep1() {
    if (!this.effectiveRecordId) {
      return "商談IDが指定されていません。";
    }
    const d = this.wizardData;
    if (!d.selectedType) {
      return "操作を選択してください。";
    }

    if (this.isOrderedCustomFieldsOnlyEdit) {
      return null;
    }

    if (d.selectedType === "New") {
      if (!d.accountName) {
        return "商談に取引先が設定されていません。";
      }
      if (!d.contractServiceName || !d.contractServiceName.trim()) {
        return "契約サービス名を入力してください。";
      }
      if (!d.contractHistoryName || !d.contractHistoryName.trim()) {
        return "契約履歴名を入力してください。";
      }
      if (!d.billingAccountId) {
        return "請求アカウントを選択してください。";
      }
      const taxError = this.validateTaxPercent(d.taxPercent);
      if (taxError) {
        return taxError;
      }
      return null;
    }

    if (!d.contractServiceId) {
      return "契約サービスを選択してください。";
    }
    if (!d.contractServiceName || !d.contractServiceName.trim()) {
      return "契約サービス名を入力してください。";
    }
    if (!d.contractHistoryId) {
      return "選択した契約サービスに、受注済み（新規／追加変更／更新）の契約履歴がありません。";
    }
    if (!d.contractHistoryName || !d.contractHistoryName.trim()) {
      return "契約履歴名を入力してください。";
    }
    if (!d.serviceLifecycle) {
      return "ライフサイクルが未設定です。先にバックフィルしてください。";
    }
    if (!d.billingAccountId) {
      return "請求アカウントを選択してください。";
    }
    if (d.selectedType === "Change" && d.serviceLifecycle === "Spot") {
      return this.validateTaxPercent(d.taxPercent);
    }
    if (
      (d.selectedType === "Change" ||
        d.selectedType === "Renew" ||
        d.selectedType === "Cancel") &&
      d.renewEligible === false
    ) {
      return this.renewEligibleFalseMessage(d.selectedType);
    }
    if (
      (d.selectedType === "Renew" || d.selectedType === "Cancel") &&
      d.serviceLifecycle === "Spot"
    ) {
      return "都度契約では更新／解約は使えません。一回課金だけの追加変更を使ってください。";
    }
    return this.validateTaxPercent(d.taxPercent);
  }

  /**
   * Step2（詳細情報）: 期間・商品・全追加項目。保存時に使う。
   */
  validateStep2() {
    const d = this.wizardData;
    const type = d.selectedType;

    if (this.isOrderedCustomFieldsOnlyEdit) {
      return this.validateOrderedCustomFieldsOnly(d);
    }

    const taxError = this.validateTaxPercent(d.taxPercent);
    if (taxError) {
      return taxError;
    }

    if (!d.contractHistoryName || !d.contractHistoryName.trim()) {
      return "契約履歴名を入力してください。";
    }

    if (type === "New") {
      const serviceCustomError = validateCustomFieldMaps(
        this.serviceFieldDefinitions,
        d.contractServiceCustomFields,
        "契約サービス",
        undefined,
        d.selectedType
      );
      if (serviceCustomError) {
        return serviceCustomError;
      }
    }
    const historyCustomError = validateCustomFieldMaps(
      this.historyFieldDefinitions,
      d.contractHistoryCustomFields,
      "契約履歴",
      undefined,
      d.selectedType
    );
    if (historyCustomError) {
      return historyCustomError;
    }

    const periodStartLabel = "継続課金の期間開始日";
    const periodEndLabel = "継続課金の期間終了日";
    const effectiveDateLabel = "継続課金の切替日";

    const hasRecurringLines = (d.selectedProducts || []).some(
      (row) =>
        row &&
        row.productId &&
        Number(row.quantity) > 0 &&
        row.billingType === "継続課金"
    );
    const isNewSpotOnly = type === "New" && !hasRecurringLines;
    const isSpotChange = type === "Change" && d.serviceLifecycle === "Spot";

    if (isNewSpotOnly || isSpotChange) {
      // 契約期間・切替日は不要
    } else {
      if (!d.contractStartDate) {
        return `${periodStartLabel}を入力してください。`;
      }
      // Change の切替日は validateChangeEffectiveDate 側で一回追加のみを許容
      if (type !== "Change") {
        if (!d.contractEffectiveDate) {
          return `${effectiveDateLabel}を入力してください。`;
        }
        if (!isValidIsoDate(d.contractEffectiveDate)) {
          return `${effectiveDateLabel}は YYYY-MM-DD 形式で入力してください。`;
        }
      }
    }

    if (type === "New" && !isNewSpotOnly) {
      const effectiveDateError = validateNewEffectiveDate(
        d.contractStartDate,
        d.contractEffectiveDate
      );
      if (effectiveDateError) {
        return effectiveDateError;
      }
    }

    if (type === "Renew") {
      const effectiveDateError = validateRenewEffectiveDate(
        d.contractStartDate,
        d.contractEffectiveDate,
        d.previousTermEndDate
      );
      if (effectiveDateError) {
        return effectiveDateError;
      }
    }

    if (type === "Change" && !isSpotChange) {
      if (d.renewEligible === false) {
        return this.renewEligibleFalseMessage("Change");
      }
      const periodError = validateChangePeriodDates(
        d.contractStartDate,
        d.contractEndDate,
        d.previousTermStartDate,
        d.previousTermEndDate
      );
      if (periodError) {
        return periodError;
      }
      const effectiveDateError = validateChangeEffectiveDate(
        d.contractEffectiveDate,
        d.previousTermStartDate,
        d.previousTermEndDate,
        d.contractStartDate,
        d.selectedProducts
      );
      if (effectiveDateError) {
        return effectiveDateError;
      }
    }

    if (type === "Cancel") {
      if (d.renewEligible === false) {
        return this.renewEligibleFalseMessage("Cancel");
      }
      if (!d.contractEndDate) {
        return "解約日が取得できません。";
      }
      if (d.contractStartDate !== d.contractEndDate) {
        return "解約日の開始日と終了日が一致しません。";
      }
      const cancelEffectiveError = validateCancelEffectiveDate(
        d.contractStartDate,
        d.contractEffectiveDate,
        d.previousTermEndDate
      );
      if (cancelEffectiveError) {
        return cancelEffectiveError;
      }
      const cancelProductsError = validateCancelProducts(d.selectedProducts);
      if (cancelProductsError) {
        return cancelProductsError;
      }
      return null;
    }

    if (
      (type === "New" && !isNewSpotOnly) ||
      type === "Renew" ||
      (type === "Change" && !isSpotChange)
    ) {
      if (!d.contractEndDate) {
        return `${periodEndLabel}を入力してください。`;
      }
    }

    if (
      (type === "Change" || type === "Renew" || type === "New") &&
      !isNewSpotOnly &&
      !isSpotChange
    ) {
      if (
        d.contractStartDate &&
        d.contractEndDate &&
        d.contractStartDate > d.contractEndDate
      ) {
        return `${periodStartLabel}は${periodEndLabel}以前の日付を入力してください。`;
      }
    }

    const products = d.selectedProducts || [];

    const amountEntryError = validateAmountEntryUnitPrices(products);
    if (amountEntryError) {
      return amountEntryError;
    }

    if (type === "New") {
      // 仕様: Core 第4.3.5節、第4.5.2節、第1.1.8節。
      const newError = validateNewProducts(
        products,
        isNewSpotOnly ? "" : d.contractStartDate,
        isNewSpotOnly ? "" : d.contractEndDate
      );
      if (newError) {
        return newError;
      }
      return this.validateProductCustomFields(products);
    }

    if (isSpotChange) {
      // 仕様: Core 第5.1節、第3.4.2節、第1.1.10節、第1.1.8節。
      // 一回課金 Type=New 限定は画面で止める。共通明細規則は validateNewProducts。
      const spotError = validateSpotChangeProducts(products);
      if (spotError) {
        return spotError;
      }
      return this.validateProductCustomFields(products);
    }

    if (type === "Renew") {
      if (d.renewEligible === false) {
        return this.renewEligibleFalseMessage("Renew");
      }
      const renewError = validateRenewProducts(
        products,
        d.contractStartDate,
        d.contractEndDate,
        d.previousTermEndDate
      );
      if (renewError) {
        return renewError;
      }
      return this.validateProductCustomFields(products);
    }

    if (type === "Change" && !isSpotChange) {
      if (d.renewEligible === false) {
        return this.renewEligibleFalseMessage("Change");
      }
      const changeError = validateChangeProducts(
        products,
        d.contractStartDate,
        d.contractEndDate,
        d.contractEffectiveDate,
        d.changeSourceProducts,
        d.previousTermStartDate,
        d.previousTermEndDate
      );
      if (changeError) {
        return changeError;
      }
      return this.validateProductCustomFields(products);
    }

    for (let i = 0; i < products.length; i++) {
      const line = products[i];
      const periodError = validateBillingPeriod(line);
      if (periodError) {
        const label = productTypeDisplayLabel(line.recordType, line.typeLabel);
        return `商品明細（${label}）: ${periodError}`;
      }
      if (line.amount == null && line.productId) {
        const qty = Number(line.quantity);
        if (Number.isNaN(qty) || qty !== 0) {
          const label = productTypeDisplayLabel(line.recordType, line.typeLabel);
          return `商品明細（${label}）: 金額を計算できません。期間を確認してください。`;
        }
      }
    }

    return this.validateProductCustomFields(products);
  }

  validateOrderedCustomFieldsOnly(d) {
    const serviceCustomError = validateCustomFieldMaps(
      this.serviceFieldDefinitions,
      d.contractServiceCustomFields,
      "契約サービス",
      undefined,
      d.selectedType
    );
    if (serviceCustomError) {
      return serviceCustomError;
    }
    const historyCustomError = validateCustomFieldMaps(
      this.displayedHistoryFieldDefinitions,
      d.contractHistoryCustomFields,
      "契約履歴",
      undefined,
      d.selectedType
    );
    if (historyCustomError) {
      return historyCustomError;
    }
    return this.validateProductCustomFields(d.selectedProducts || [], true);
  }

  validateProductCustomFields(products, includeReadonly = false) {
    if (!products || products.length === 0) {
      return null;
    }
    const wizardType = this.wizardData?.selectedType || "";
    for (let i = 0; i < products.length; i++) {
      const line = products[i];
      if (!line || !line.productId) {
        continue;
      }
      if (!includeReadonly && line.isReadonly === true) {
        continue;
      }
      if (isChangeOriginalLine(line)) {
        continue;
      }
      const error = validateCustomFieldMaps(
        this.productFieldDefinitions,
        line.customFields,
        `商品明細（${productTypeDisplayLabel(line.recordType, line.typeLabel)}）`,
        line.productVisibilityContext,
        wizardType
      );
      if (error) {
        return error;
      }
    }
    return null;
  }

  /**
   * Apex saveEstimate.applicationDate 向け。
   * 履歴カスタム項目 ApplicationDate__c があればそれを渡す（無ければ null）。
   */
  resolveApplicationDateForSave() {
    const customFields = this.wizardData.contractHistoryCustomFields || {};
    const raw = customFields.ApplicationDate__c;
    if (raw == null || raw === "") {
      return null;
    }
    return String(raw);
  }

  async handleSave() {
    try {
      const type = this.wizardData.selectedType;
      if (
        type !== "New" &&
        type !== "Change" &&
        type !== "Renew" &&
        type !== "Cancel"
      ) {
        this.showToast(
          "情報",
          "新規、追加変更、更新、解約のみ保存できます。",
          "info"
        );
        return;
      }
      if (this.wizardFieldConfigError) {
        this.validationAlert = buildWizardValidationAlert(
          this.wizardFieldConfigError
        );
        this.scrollValidationAlertIntoView();
        return;
      }

      this.dispatch({ type: WIZARD_ACTIONS.SAVE_START });
      try {
        if (!this._pendingOperationKey) {
          this._pendingOperationKey = await issueEstimateOperationKey();
        }
        const result = await saveEstimate({
          opportunityId: this.effectiveRecordId,
          selectedType: type,
          contractServiceName: this.wizardData.contractServiceName,
          contractHistoryName: this.wizardData.contractHistoryName,
          contractServiceId: this.wizardData.contractServiceId || null,
          previousHistoryId: this.wizardData.contractHistoryId || null,
          contractStartDate: this.wizardData.contractStartDate,
          contractEndDate: this.wizardData.contractEndDate,
          effectiveDate: this.wizardData.contractEffectiveDate,
          applicationDate: null,
          productsJson: JSON.stringify(this.wizardData.selectedProducts || []),
          estimateRemarkMasterId:
            this.wizardData.estimateRemarkMasterId || null,
          remarksText: this.wizardData.estimateRemarks || null,
          billingAccountId: this.wizardData.billingAccountId || null,
          copyFromHistoryId: this.isEditMode
            ? null
            : this.copyFromHistoryId || null,
          editHistoryId: this.isEditMode ? this.editHistoryId || null : null,
          contractServiceCustomFieldsJson: JSON.stringify(
            type === "New"
              ? this.wizardData.contractServiceCustomFields || {}
              : {}
          ),
          contractHistoryCustomFieldsJson: JSON.stringify(
            this.wizardData.contractHistoryCustomFields || {}
          ),
          expectedLastModifiedToken: this.isEditMode
            ? this.wizardData.lastModifiedToken || null
            : null,
          taxPercent:
            this.wizardData.taxPercent == null ||
            this.wizardData.taxPercent === ""
              ? null
              : Number(this.wizardData.taxPercent),
          estimateDate: this.wizardData.estimateDate || null,
          estimateValidDate: this.wizardData.estimateValidDate || null,
          estimateSendContactId: this.wizardData.estimateSendContactId || null,
          businessOperationKey: this._pendingOperationKey
        });
        // 連続保存用に楽観ロックトークンを更新
        if (result?.lastModifiedToken) {
          this.dispatch({
            type: WIZARD_ACTIONS.MERGE_STEP2,
            fields: { lastModifiedToken: result.lastModifiedToken }
          });
        }
        if (result?.businessOperationKey) {
          this._pendingOperationKey = result.businessOperationKey;
        }
        this._saveSucceededThisSession = true;
        this._pendingOperationKey = "";
        this.showToast(
          "成功",
          this.isEditMode
            ? "見積データを更新しました。"
            : "見積データを保存しました。",
          "success"
        );
        this.dispatch({ type: WIZARD_ACTIONS.SAVE_END });
        if (this.modalMode) {
          requestEstimateWizardClose(this, {
            refresh: true,
            opportunityId: this.effectiveRecordId,
            contractHistoryId: result?.contractHistoryId,
            navigateToContractHistoryId: result?.contractHistoryId
          });
          this.dispatchEvent(
            new CustomEvent("estimatesaved", {
              bubbles: true,
              composed: true,
              detail: {
                opportunityId: this.effectiveRecordId,
                contractHistoryId: result?.contractHistoryId
              }
            })
          );
          return;
        }
        this.redirectToContractHistory(result?.contractHistoryId);
      } catch (error) {
        this.validationAlert = resolveSaveErrorAlert(error);
        this.scrollValidationAlertIntoView();
      } finally {
        this.dispatch({ type: WIZARD_ACTIONS.SAVE_END });
      }
    } finally {
      this._saveInFlight = false;
    }
  }

  handleClose() {
    if (this.isSaving) {
      return;
    }
    if (this.hasOpenConfirm) {
      if (this._confirmState && this._confirmState.kind === "close") {
        return;
      }
      // 閉じる意思を優先し、備考／同商品確認はキャンセル扱いして差し替える
      this.dismissOpenConfirm();
    }
    if (!this._saveSucceededThisSession) {
      this.openConfirm(
        { kind: "close" },
        "入力内容は保存されていません。破棄してよろしいですか？"
      );
      return;
    }
    this.performClose();
  }

  performClose() {
    if (this.modalMode) {
      requestEstimateWizardClose(this, {
        refresh: false,
        opportunityId: this.effectiveRecordId,
        contractHistoryId: this.editHistoryId || this.copyFromHistoryId || null
      });
      return;
    }
    this.closeWizard();
  }

  closeWizard() {
    if (typeof window === "undefined") {
      return;
    }
    window.close();
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(() => {
      if (!window.closed) {
        this.redirectToOpportunity();
      }
    }, 150);
  }

  // NavigationMixin は使わず window.location で遷移（タブ閉じ失敗時のフォールバック含む）。
  redirectToContractHistory(contractHistoryId) {
    if (typeof window === "undefined") {
      return;
    }
    if (contractHistoryId) {
      window.location.href = `${this.getLightningBase()}/lightning/r/ContractHistory__c/${contractHistoryId}/view`;
      return;
    }
    this.redirectToOpportunity();
  }

  redirectToOpportunity() {
    if (typeof window === "undefined") {
      return;
    }
    const recordId = this.effectiveRecordId;
    if (recordId) {
      window.location.href = `${this.getLightningBase()}/lightning/r/Opportunity/${recordId}/view`;
      return;
    }
    window.history.back();
  }

  showValidationAlert(message) {
    // エラー表示に差し替える前に、開いていた確認はキャンセル扱い
    this.dismissOpenConfirm();
    this._skipSameProductNewConfirm = false;
    this.validationAlert = buildWizardValidationAlert(message);
    this.scrollValidationAlertIntoView();
  }

  showConfirmationAlert(message) {
    this.validationAlert = buildConfirmValidationAlert(message);
    this.scrollValidationAlertIntoView();
  }

  clearValidationAlert() {
    this.validationAlert = null;
  }

  scrollValidationAlertIntoView() {
    if (typeof window === "undefined") {
      return;
    }
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    window.requestAnimationFrame(() => {
      const alertElement = this.template.querySelector(
        '[data-id="wizard-validation-alert"]'
      );
      if (alertElement) {
        alertElement.scrollIntoView({
          behavior: "smooth",
          block: "nearest"
        });
      }
    });
  }

  showToast(title, message, variant) {
    this.dispatchEvent(
      new ShowToastEvent({
        title,
        message,
        variant: variant || "info",
        mode: "dismissable"
      })
    );
  }
}
