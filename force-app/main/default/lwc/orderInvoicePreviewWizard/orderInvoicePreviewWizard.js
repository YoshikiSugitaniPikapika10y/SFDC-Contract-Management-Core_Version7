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
  isOrderActionBootstrapping,
  requestOrderWizardClose,
  scheduleRecordActionLoad,
  resetRecordActionLoadState
} from "c/orderWizardClose";
import resolvePreviewScope from "@salesforce/apex/OrderCreateController.resolvePreviewScope";
import getInvoicePreview from "@salesforce/apex/OrderCreateController.getInvoicePreview";
import updateInvoiceLineAmounts from "@salesforce/apex/OrderCreateController.updateInvoiceLineAmounts";
import updateInvoiceLineAcceptanceEndDate from "@salesforce/apex/OrderCreateController.updateInvoiceLineAcceptanceEndDate";
import splitInvoiceByDate from "@salesforce/apex/OrderCreateController.splitInvoiceByDate";
import splitInvoiceByBillingAccount from "@salesforce/apex/OrderCreateController.splitInvoiceByBillingAccount";
import moveLinesToExistingInvoice from "@salesforce/apex/OrderCreateController.moveLinesToExistingInvoice";
import splitLinesInPlace from "@salesforce/apex/OrderCreateController.splitLinesInPlace";
import resetLatestVersionInvoicesToPostOrder from "@salesforce/apex/OrderCreateController.resetLatestVersionInvoicesToPostOrder";
import getBillingAccountOptionsForPreview from "@salesforce/apex/OrderCreateController.getBillingAccountOptionsForPreview";
import updateInvoiceHeaderAndDates from "@salesforce/apex/OrderCreateController.updateInvoiceHeaderAndDates";
import applyBillingAccountContent from "@salesforce/apex/OrderCreateController.applyBillingAccountContent";
import cancelConfirmedFromPreview from "@salesforce/apex/OrderCreateController.cancelConfirmedFromPreview";

const VERSION_CONFLICT_MESSAGE =
  "他のユーザーが先に更新しました。画面を開き直してから再度操作してください。";

export default class OrderInvoicePreviewWizard extends NavigationMixin(
  LightningElement
) {
  @api recordId;

  @track isTabView = false;
  @track isLoading = true;
  @track isSaving = false;
  @track errorMessage = "";
  @track contentLoadFailed = false;
  @track invoicePreview;
  @track completionNote = "";
  @track billingAccountOptions = [];
  @track previewScope;

  _onViewportResize = () => this.applyScrollSizing();
  _resizeBound = false;

  connectedCallback() {
    initializeOrderWizardFromUrl(this);
    // 開くたびに請求ボードをサーバ最新で取り直す
    resetRecordActionLoadState(this);
    scheduleRecordActionLoad(this, () => this.loadPreview());
    window.addEventListener("resize", this._onViewportResize);
    this._resizeBound = true;
  }

  disconnectedCallback() {
    if (this._resizeBound) {
      window.removeEventListener("resize", this._onViewportResize);
      this._resizeBound = false;
    }
  }

  renderedCallback() {
    this.applyScrollSizing();
    requestAnimationFrame(() => this.applyScrollSizing());
    scheduleRecordActionLoad(this, () => this.loadPreview());
  }

  get scrollRoot() {
    return this.template.querySelector(".preview-page");
  }

  /**
   * 仕様: Core 第7.7.0節。縦スクローラはボード自身が1本。枠に入れ子しない。
   * モーダル枠への貼り付けは record-action の resizeQuickActionPanel。
   * ここは自ホストと .preview-page だけ。親 DOM は触らない（LWS で無効）。
   */
  applyScrollSizing() {
    const host = this.template.host;
    const root = this.scrollRoot;
    if (!host || !host.style) {
      return;
    }
    host.style.setProperty("height", "100%");
    host.style.setProperty("max-height", "100%");
    host.style.setProperty("min-height", "0");
    host.style.setProperty("overflow", "hidden");
    if (!root) {
      return;
    }
    const box = host.getBoundingClientRect();
    const fromHost = box && box.height ? box.height : 0;
    const available = Math.max(fromHost, this.measureBoardHeight(host, root));
    if (!available) {
      return;
    }
    const px = `${Math.round(available)}px`;
    root.style.setProperty("--preview-scroll-max", px);
    root.style.setProperty("height", "100%");
    root.style.setProperty("max-height", "100%");
  }

  measureBoardHeight(host, root) {
    const box = (root || host).getBoundingClientRect();
    const top = Math.max(box.top, 0);
    const viewportHeight =
      window.innerHeight ||
      (document.scrollingElement || document.documentElement).clientHeight ||
      0;
    const bottomGap = this.isTabView ? 8 : 24;
    return viewportHeight
      ? Math.max(viewportHeight - top - bottomGap, 240)
      : 0;
  }

  @wire(CurrentPageReference)
  setCurrentPageReference(pageRef) {
    const recordId = readOrderWizardRecordId(pageRef);
    if (recordId) {
      // eslint-disable-next-line @lwc/lwc/no-api-reassignments
      this.recordId = recordId;
    }
    this.isTabView = isOrderWizardTabView(pageRef, "preview");
  }

  get pageClass() {
    return this.isTabView
      ? "preview-page preview-page_tab"
      : "preview-page preview-page_modal";
  }

  get previewHistoryId() {
    return this.previewScope?.contractHistoryId || null;
  }

  get tableInitialVersion() {
    return this.previewScope?.initialVersion || "";
  }

  get tableInitialInvoiceId() {
    return this.previewScope?.initialInvoiceId || "";
  }

  // 仕様: Core 第7.7.0節、第4.3.11節。開いたままの読み直しでは表を外さない。
  async loadPreview() {
    if (!this.recordId) {
      return;
    }

    const keepOpenBoard = Boolean(this.invoicePreview);
    if (!keepOpenBoard) {
      this.isLoading = true;
      this.invoicePreview = undefined;
    }
    this.errorMessage = "";
    this.contentLoadFailed = false;
    try {
      const scope = await resolvePreviewScope({
        recordId: this.recordId
      });
      this.previewScope = scope;
      if (!scope?.canOpen) {
        this.errorMessage =
          scope?.blockReason || "請求ボードを開けません。";
        return;
      }

      this.invoicePreview = await getInvoicePreview({
        contractHistoryId: scope.contractHistoryId
      });
      this.billingAccountOptions = await getBillingAccountOptionsForPreview({
        contractHistoryId: scope.contractHistoryId
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
    this.loadPreview();
  }

  get hasPreview() {
    return Boolean(this.invoicePreview);
  }

  get showBootstrapLoading() {
    return isOrderActionBootstrapping(this);
  }

  get previewContentVersion() {
    return this.invoicePreview?.contentVersion || null;
  }

  async handleSaveLineAmounts(event) {
    const { edits, expectedTokenByInvoiceId, businessOperationKey } =
      event.detail || {};
    if (!edits?.length) {
      return;
    }
    await this.runEdit(() =>
      updateInvoiceLineAmounts({
        contractHistoryId: this.previewHistoryId,
        edits,
        expectedTokenByInvoiceId: expectedTokenByInvoiceId || {},
        businessOperationKey
      })
    );
  }

  async handleSaveAcceptanceEndDate(event) {
    const {
      lineId,
      acceptanceEndDate,
      cancellationDate,
      journalPreviewText,
      expectedContentVersion,
      businessOperationKey
    } = event.detail || {};
    if (!lineId) {
      return;
    }
    const saved = await this.runEdit(
      () =>
        updateInvoiceLineAcceptanceEndDate({
          contractHistoryId: this.previewHistoryId,
          lineId,
          acceptanceEndDate: acceptanceEndDate || null,
          expectedContentVersion:
            expectedContentVersion || this.previewContentVersion,
          cancellationDate: cancellationDate || null,
          businessOperationKey
        }),
      journalPreviewText || ""
    );
    if (
      !saved &&
      String(this.errorMessage || "").includes("取消基準日が必要")
    ) {
      const table = this.template.querySelector("c-order-invoice-preview-table");
      if (table && typeof table.showAcceptanceCancelDateRequired === "function") {
        table.showAcceptanceCancelDateRequired(lineId, acceptanceEndDate);
      }
    }
  }

  async handleSaveBillingHeader(event) {
    const {
      invoiceId,
      invoiceDate,
      paymentScheduledDate,
      billingAddressee,
      billingEmailTo,
      billingEmailCc,
      billingEmailBcc,
      expectedContentVersion,
      businessOperationKey,
      extraFieldValues
    } = event.detail || {};
    if (!invoiceId) {
      return;
    }
    if (!invoiceDate) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "請求日を入力してください",
          message: "請求日は必須です。",
          variant: "error",
          mode: "dismissable"
        })
      );
      return;
    }
    if (!paymentScheduledDate) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "入金予定日を入力してください",
          message: "入金予定日は必須です。",
          variant: "error",
          mode: "dismissable"
        })
      );
      return;
    }
    const saved = await this.runEdit(() =>
      updateInvoiceHeaderAndDates({
        contractHistoryId: this.previewHistoryId,
        invoiceId,
        invoiceDate,
        paymentScheduledDate,
        billingAddressee: "",
        billingEmailTo: "",
        billingEmailCc: "",
        billingEmailBcc: "",
        taxPercent: null,
        expectedContentVersion:
          expectedContentVersion || this.previewContentVersion,
        businessOperationKey,
        extraFieldValues
      })
    );
    if (saved) {
      const table = this.template.querySelector(
        "c-order-invoice-preview-table"
      );
      if (table && typeof table.clearBillingEditState === "function") {
        table.clearBillingEditState();
      }
    }
  }

  async handleSplitInvoice(event) {
    const {
      mode,
      sourceInvoiceId,
      newInvoiceDate,
      newPaymentScheduledDate,
      newBillingAccountId,
      splitLines,
      expectedContentVersion,
      businessOperationKey
    } = event.detail || {};
    if (!sourceInvoiceId || !(splitLines || []).length) {
      return;
    }
    if (!newInvoiceDate) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "請求日を入力してください",
          message: "分割先の請求日は必須です。",
          variant: "error",
          mode: "dismissable"
        })
      );
      return;
    }
    if (!newPaymentScheduledDate) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "入金予定日を入力してください",
          message: "分割先の入金予定日は必須です。",
          variant: "error",
          mode: "dismissable"
        })
      );
      return;
    }
    if (mode === "billingAccount") {
      if (!newBillingAccountId) {
        return;
      }
      await this.runEdit(() =>
        splitInvoiceByBillingAccount({
          contractHistoryId: this.previewHistoryId,
          sourceInvoiceId,
          newBillingAccountId,
          newInvoiceDate,
          newPaymentScheduledDate,
          splitLines,
          expectedContentVersion:
            expectedContentVersion || this.previewContentVersion,
          businessOperationKey
        })
      );
      return;
    }
    await this.runEdit(() =>
      splitInvoiceByDate({
        contractHistoryId: this.previewHistoryId,
        sourceInvoiceId,
        newInvoiceDate,
        newPaymentScheduledDate,
        splitLines,
        expectedContentVersion:
          expectedContentVersion || this.previewContentVersion,
        businessOperationKey
      })
    );
  }

  async handleMoveLines(event) {
    const {
      sourceInvoiceId,
      targetInvoiceId,
      lineIds,
      expectedContentVersion,
      expectedTargetContentVersion,
      businessOperationKey
    } = event.detail || {};
    if (!sourceInvoiceId || !targetInvoiceId || !(lineIds || []).length) {
      return;
    }
    await this.runEdit(() =>
      moveLinesToExistingInvoice({
        contractHistoryId: this.previewHistoryId,
        sourceInvoiceId,
        targetInvoiceId,
        lineIds,
        expectedContentVersion:
          expectedContentVersion || this.previewContentVersion,
        expectedTargetContentVersion:
          expectedTargetContentVersion ||
          expectedContentVersion ||
          this.previewContentVersion,
        businessOperationKey
      })
    );
  }

  async handleSplitLinesInPlace(event) {
    const {
      invoiceId,
      splitLines,
      expectedContentVersion,
      businessOperationKey
    } = event.detail || {};
    if (!invoiceId || !(splitLines || []).length) {
      return;
    }
    await this.runEdit(() =>
      splitLinesInPlace({
        contractHistoryId: this.previewHistoryId,
        invoiceId,
        splitLines,
        expectedContentVersion:
          expectedContentVersion || this.previewContentVersion,
        businessOperationKey
      })
    );
  }

  async handleResetPostOrder(event) {
    const {
      versionValue,
      expectedTokenByInvoiceId,
      businessOperationKey
    } = event.detail || {};
    if (!versionValue) {
      return;
    }
    await this.runEdit(() =>
      resetLatestVersionInvoicesToPostOrder({
        contractHistoryId: this.previewHistoryId,
        versionValue: String(versionValue),
        expectedTokenByInvoiceId: expectedTokenByInvoiceId || {},
        businessOperationKey
      })
    );
  }

  async handleApplyBillingAccountContent(event) {
    const { invoiceId, expectedContentVersion, businessOperationKey } =
      event.detail || {};
    if (!invoiceId) {
      return;
    }
    await this.runEdit(() =>
      applyBillingAccountContent({
        contractHistoryId: this.previewHistoryId,
        invoiceId,
        expectedContentVersion:
          expectedContentVersion || this.previewContentVersion,
        businessOperationKey
      })
    );
  }

  async handleCancelConfirmed(event) {
    const {
      invoiceId,
      cancellationReason,
      cancellationReasonText,
      cancellationDate,
      journalPreviewText,
      customerNotice,
      expectedContentVersion,
      businessOperationKey
    } = event.detail || {};
    if (!invoiceId) {
      return;
    }
    await this.runEdit(
      () =>
        cancelConfirmedFromPreview({
          contractHistoryId: this.previewHistoryId,
          invoiceId,
          cancellationReason,
          cancellationReasonText: cancellationReasonText || null,
          cancellationDate: cancellationDate || null,
          expectedContentVersion:
            expectedContentVersion || this.previewContentVersion,
          businessOperationKey
        }),
      [journalPreviewText, customerNotice].filter((part) => part).join("\n")
    );
  }

  async handleInvoiceOpsComplete() {
    await this.loadPreview();
  }

  async runEdit(action, successMessage) {
    if (this.isSaving) {
      return false;
    }
    this.isSaving = true;
    this.errorMessage = "";
    try {
      this.invoicePreview = await action();
      this.completionNote = "請求情報を保存しました。";
      return true;
    } catch (error) {
      this.errorMessage = this.reduceError(error);
      this.dispatchEvent(
        new ShowToastEvent({
          title: "保存エラー",
          message: this.errorMessage,
          variant: "error"
        })
      );
      // 仕様: Core 第7.9.7節・第4.3.12節。版比較失敗時はボード全体を読み直す。
      if (this.errorMessage === VERSION_CONFLICT_MESSAGE) {
        await this.loadPreview();
      }
      return false;
    } finally {
      this.isSaving = false;
    }
  }

  handleClose() {
    this.closeAction({ refresh: false });
  }

  closeAction({ refresh = false } = {}) {
    if (this.isTabView) {
      closeOrderWizardTab(this, {
        recordId: this.recordId,
        refresh
      });
      return;
    }
    requestOrderWizardClose(this, { recordId: this.recordId, refresh });
  }

  reduceError(error) {
    const alert = resolveSaveErrorAlert(error);
    return alert.messages.map((entry) => entry.text).join("\n");
  }

  /**
   * 仕様: Core 第7.7.0節。ホイールはボードの1本へ届ける。
   * combobox の listbox 等、ポインタ直下の小スクローラだけ既定に任せる。
   * 枠のスクローラへは連鎖しない。
   */
  handlePreviewWheel(event) {
    if (!event || event.ctrlKey) {
      return;
    }
    const deltaY = this.resolveWheelDeltaY(event);
    if (!deltaY) {
      return;
    }
    const path = event.composedPath ? event.composedPath() : [];
    const root = this.scrollRoot;
    if (this.findInnerScroller(path, deltaY, root)) {
      return;
    }
    if (!root || !this.canScrollY(root)) {
      return;
    }
    if (this.canConsumeY(root, deltaY)) {
      root.scrollTop += deltaY;
    }
    event.preventDefault();
  }

  findInnerScroller(path, deltaY, root) {
    for (const node of path) {
      if (!node || node.nodeType !== 1) {
        continue;
      }
      if (node === root || node === this.template.host) {
        break;
      }
      if (!this.isSmallScroller(node) || !this.canConsumeY(node, deltaY)) {
        continue;
      }
      return node;
    }
    return null;
  }

  isSmallScroller(el) {
    const role = el.getAttribute ? el.getAttribute("role") : "";
    if (role === "listbox" || role === "menu" || role === "list") {
      return true;
    }
    const tag = el.tagName;
    if (tag === "TEXTAREA" || tag === "SELECT") {
      return true;
    }
    return Boolean(
      el.classList &&
        (el.classList.contains("slds-listbox") ||
          el.classList.contains("slds-dropdown"))
    );
  }

  resolveWheelDeltaY(event) {
    let delta =
      event.shiftKey && event.deltaY === 0 ? event.deltaX : event.deltaY;
    if (!delta) {
      return 0;
    }
    if (event.deltaMode === 1) {
      delta *= 16;
    } else if (event.deltaMode === 2) {
      delta *=
        (document.scrollingElement || document.documentElement).clientHeight ||
        800;
    }
    return delta;
  }

  canConsumeY(el, deltaY) {
    if (!this.canScrollY(el)) {
      return false;
    }
    if (deltaY < 0) {
      return el.scrollTop > 0;
    }
    return el.scrollTop + el.clientHeight < el.scrollHeight - 1;
  }

  canScrollY(el) {
    if (!el || el.nodeType !== 1) {
      return false;
    }
    // ビューポートのスクローラは overflow が visible のままでも縦に動く
    const viewport = document.scrollingElement || document.documentElement;
    if (el !== viewport) {
      const oy = getComputedStyle(el).overflowY;
      if (oy !== "auto" && oy !== "scroll" && oy !== "overlay") {
        return false;
      }
    }
    return el.scrollHeight > el.clientHeight + 1;
  }

  dispatchEvent(event) {
    if (
      event &&
      (event.type === "lightning__showtoast" ||
        event.constructor?.name === "ShowToastEvent")
    ) {
      const detail = event.detail || {};
      if (detail.variant === "error" || !detail.variant) {
        this.errorMessage = String(detail.message || detail.title || "").replace(
          /Version/g,
          "版"
        );
        return true;
      }
      return true;
    }
    return super.dispatchEvent(event);
  }
}
