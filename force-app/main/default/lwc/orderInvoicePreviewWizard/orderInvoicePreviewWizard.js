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
  requestOrderWizardClose,
  scheduleRecordActionLoad,
  resetRecordActionLoadState
} from "c/orderWizardClose";
import getOrderContext from "@salesforce/apex/OrderCreateController.getOrderContext";
import getInvoicePreview from "@salesforce/apex/OrderCreateController.getInvoicePreview";
import updateInvoiceLineAmounts from "@salesforce/apex/OrderCreateController.updateInvoiceLineAmounts";
import updateInvoiceDates from "@salesforce/apex/OrderCreateController.updateInvoiceDates";
import splitInvoiceByDate from "@salesforce/apex/OrderCreateController.splitInvoiceByDate";
import splitInvoiceByBillingAccount from "@salesforce/apex/OrderCreateController.splitInvoiceByBillingAccount";
import moveLinesToExistingInvoice from "@salesforce/apex/OrderCreateController.moveLinesToExistingInvoice";
import splitLinesInPlace from "@salesforce/apex/OrderCreateController.splitLinesInPlace";
import resetLatestVersionInvoicesToPostOrder from "@salesforce/apex/OrderCreateController.resetLatestVersionInvoicesToPostOrder";
import getBillingAccountOptionsForPreview from "@salesforce/apex/OrderCreateController.getBillingAccountOptionsForPreview";
import updateInvoiceHeaderAndDates from "@salesforce/apex/OrderCreateController.updateInvoiceHeaderAndDates";

export default class OrderInvoicePreviewWizard extends NavigationMixin(
  LightningElement
) {
  @api recordId;

  @track isTabView = false;
  @track isLoading = true;
  @track isSaving = false;
  @track errorMessage = "";
  @track invoicePreview;
  @track billingAccountOptions = [];

  _wheelBound = false;
  _onPreviewWheel = (event) => this.handlePreviewWheel(event);

  connectedCallback() {
    initializeOrderWizardFromUrl(this);
    // 開くたびに請求プレビューをサーバ最新で取り直す
    resetRecordActionLoadState(this);
    scheduleRecordActionLoad(this, () => this.loadPreview());
    this.template.host.addEventListener("wheel", this._onPreviewWheel, {
      passive: false,
      capture: true
    });
    this._wheelBound = true;
  }

  disconnectedCallback() {
    if (!this._wheelBound) {
      return;
    }
    this.template.host.removeEventListener("wheel", this._onPreviewWheel, {
      capture: true
    });
    this._wheelBound = false;
  }

  renderedCallback() {
    scheduleRecordActionLoad(this, () => this.loadPreview());
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

  async loadPreview() {
    if (!this.recordId) {
      return;
    }

    this.isLoading = true;
    this.errorMessage = "";
    this.invoicePreview = undefined;
    try {
      const context = await getOrderContext({
        contractHistoryId: this.recordId
      });

      if (context.historyStatus === HISTORY_STATUS_ARCHIVE) {
        this.errorMessage =
          "アーカイブ済みの契約履歴では請求プレビューは利用できません。";
        return;
      }

      if (!context.isOrdered) {
        this.errorMessage =
          "Estimate 状態の契約履歴です。「受注」ボタンをご利用ください。";
        return;
      }

      this.invoicePreview = await getInvoicePreview({
        contractHistoryId: this.recordId
      });
      this.billingAccountOptions = await getBillingAccountOptionsForPreview({
        contractHistoryId: this.recordId
      });
    } catch (error) {
      this.errorMessage = this.reduceError(error);
    } finally {
      this.isLoading = false;
    }
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
    const { edits } = event.detail || {};
    if (!edits?.length) {
      return;
    }
    await this.runEdit(() =>
      updateInvoiceLineAmounts({
        contractHistoryId: this.recordId,
        edits,
        expectedContentVersion: this.previewContentVersion
      })
    );
  }

  async handleSaveInvoiceDates(event) {
    const { invoiceId, invoiceDate, paymentScheduledDate } = event.detail || {};
    if (!invoiceId) {
      return;
    }
    await this.runEdit(() =>
      updateInvoiceDates({
        contractHistoryId: this.recordId,
        invoiceId,
        invoiceDate: invoiceDate || null,
        paymentScheduledDate: paymentScheduledDate || null,
        expectedContentVersion: this.previewContentVersion
      })
    );
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
      taxPercent
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
    if (taxPercent == null || taxPercent === "") {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "税率を入力してください",
          message:
            "税率は必須です。0% で運用する場合は 0 を明示的に入力してください。",
          variant: "error",
          mode: "dismissable"
        })
      );
      return;
    }
    const taxPercentNumber = Number(taxPercent);
    if (
      !Number.isFinite(taxPercentNumber) ||
      taxPercentNumber < 0 ||
      taxPercentNumber > 100
    ) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "税率が不正です",
          message: "税率は 0〜100 の数値で入力してください。",
          variant: "error",
          mode: "dismissable"
        })
      );
      return;
    }
    // 日付＋宛名／メール／税率は 1 Apex・1 DML。片側だけ成功してエラー表示、を防ぐ。
    const saved = await this.runEdit(() =>
      updateInvoiceHeaderAndDates({
        contractHistoryId: this.recordId,
        invoiceId,
        invoiceDate,
        paymentScheduledDate,
        billingAddressee: billingAddressee ?? "",
        billingEmailTo: billingEmailTo ?? "",
        billingEmailCc: billingEmailCc ?? "",
        billingEmailBcc: billingEmailBcc ?? "",
        taxPercent: taxPercentNumber,
        expectedContentVersion: this.previewContentVersion
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
      splitLines
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
          contractHistoryId: this.recordId,
          sourceInvoiceId,
          newBillingAccountId,
          newInvoiceDate,
          newPaymentScheduledDate,
          splitLines,
          expectedContentVersion: this.previewContentVersion
        })
      );
      return;
    }
    await this.runEdit(() =>
      splitInvoiceByDate({
        contractHistoryId: this.recordId,
        sourceInvoiceId,
        newInvoiceDate,
        newPaymentScheduledDate,
        splitLines,
        expectedContentVersion: this.previewContentVersion
      })
    );
  }

  async handleMoveLines(event) {
    const { sourceInvoiceId, targetInvoiceId, lineIds } = event.detail || {};
    if (!sourceInvoiceId || !targetInvoiceId || !(lineIds || []).length) {
      return;
    }
    await this.runEdit(() =>
      moveLinesToExistingInvoice({
        contractHistoryId: this.recordId,
        sourceInvoiceId,
        targetInvoiceId,
        lineIds,
        expectedContentVersion: this.previewContentVersion
      })
    );
  }

  async handleSplitLinesInPlace(event) {
    const { invoiceId, splitLines } = event.detail || {};
    if (!invoiceId || !(splitLines || []).length) {
      return;
    }
    await this.runEdit(() =>
      splitLinesInPlace({
        contractHistoryId: this.recordId,
        invoiceId,
        splitLines,
        expectedContentVersion: this.previewContentVersion
      })
    );
  }

  async handleResetPostOrder(event) {
    const { versionValue } = event.detail || {};
    if (!versionValue) {
      return;
    }
    await this.runEdit(() =>
      resetLatestVersionInvoicesToPostOrder({
        contractHistoryId: this.recordId,
        versionValue: String(versionValue),
        expectedContentVersion: this.previewContentVersion
      })
    );
  }

  async runEdit(action) {
    if (this.isSaving) {
      return false;
    }
    this.isSaving = true;
    this.errorMessage = "";
    try {
      this.invoicePreview = await action();
      this.dispatchEvent(
        new ShowToastEvent({
          title: "保存しました",
          message: "請求正本を更新しました。",
          variant: "success"
        })
      );
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
   * 商品名・金額セル等がホイールを握っても、モーダルは .preview-table-area、
   * タブは外側スクローラへ渡す。document へ誤って preventDefault しない。
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
    const target = path[0] || event.target;
    if (this.isNativeScrollField(target)) {
      return;
    }
    const scroller = this.resolvePreviewScroller();
    if (!scroller || !this.canScrollY(scroller)) {
      return;
    }
    scroller.scrollTop += deltaY;
    event.preventDefault();
  }

  resolvePreviewScroller() {
    if (!this.isTabView) {
      const area = this.template.querySelector(".preview-table-area");
      if (area && this.canScrollY(area)) {
        return area;
      }
    }
    let el = this.template.host.parentElement;
    if (!el) {
      const root = this.template.host.getRootNode();
      if (root instanceof ShadowRoot) {
        el = root.host;
      }
    }
    while (el) {
      if (this.canScrollY(el)) {
        return el;
      }
      if (el.parentElement) {
        el = el.parentElement;
      } else {
        const root = el.getRootNode && el.getRootNode();
        if (root instanceof ShadowRoot && root.host) {
          el = root.host;
        } else {
          break;
        }
      }
    }
    const doc = document.scrollingElement || document.documentElement;
    return this.canScrollY(doc) ? doc : null;
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

  isNativeScrollField(target) {
    let node = target;
    if (node && node.nodeType === Node.TEXT_NODE) {
      node = node.parentElement;
    }
    while (node && node.nodeType === 1) {
      const tag = node.tagName;
      if (tag === "TEXTAREA") {
        return true;
      }
      if (node === this.template.host) {
        break;
      }
      const root = node.getRootNode && node.getRootNode();
      node =
        node.parentElement || (root instanceof ShadowRoot ? root.host : null);
    }
    return false;
  }

  canScrollY(el) {
    if (!el || el.nodeType !== 1) {
      return false;
    }
    const style = getComputedStyle(el);
    const oy = style.overflowY;
    if (oy !== "auto" && oy !== "scroll" && oy !== "overlay") {
      return false;
    }
    return el.scrollHeight > el.clientHeight + 1;
  }
}
