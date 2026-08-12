import { LightningElement, api, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import hasManageInvoiceOps from "@salesforce/customPermission/Contract_13_Can_Manage_Invoice_Ops";
import getInvoices from "@salesforce/apex/InvoiceOpsController.getInvoices";
import markInvoiced from "@salesforce/apex/InvoiceOpsController.markInvoiced";
import markExported from "@salesforce/apex/InvoiceOpsController.markExported";
import clearExportDate from "@salesforce/apex/InvoiceOpsController.clearExportDate";

/** ブラウザローカルの暦日（YYYY-MM-DD）。UTC の toISOString は使わない。 */
function formatLocalDate(date = new Date()) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

export default class InvoiceOpsPanel extends LightningElement {
  _recordId;
  _isConnected = false;

  @api
  get recordId() {
    return this._recordId;
  }
  set recordId(value) {
    const next = value || "";
    const changed = next !== (this._recordId || "");
    this._recordId = next;
    // レコード切替時は選択を捨ててから一覧を取り直す（別履歴の ID を残さない）
    if (changed && this._isConnected && this.hasPermission) {
      this.selectedIds = [];
      this.errorMessage = "";
      this.loadRows();
    }
  }

  @track rows = [];
  @track selectedIds = [];
  @track isLoading = false;
  @track errorMessage = "";
  @track operationDate = "";

  get hasPermission() {
    return hasManageInvoiceOps === true;
  }

  connectedCallback() {
    this._isConnected = true;
    this.operationDate = formatLocalDate();
    if (this.hasPermission) {
      this.loadRows();
    }
  }

  disconnectedCallback() {
    this._isConnected = false;
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  get disableActions() {
    return (
      !this.hasPermission ||
      this.isLoading ||
      this.actionInvoiceIds.length === 0
    );
  }

  get selectedCountLabel() {
    return `選択 ${this.actionInvoiceIds.length} 件`;
  }

  /** 画面上の行に存在する選択だけ（切替後の幽霊 ID を送らない） */
  get actionInvoiceIds() {
    const visible = new Set((this.rows || []).map((row) => row.id));
    return (this.selectedIds || []).filter((id) => visible.has(id));
  }

  async loadRows() {
    if (!this.hasPermission) {
      this.rows = [];
      this.selectedIds = [];
      return;
    }
    if (!this.recordId) {
      this.rows = [];
      this.selectedIds = [];
      return;
    }
    this.isLoading = true;
    this.errorMessage = "";
    const requestRecordId = this.recordId;
    try {
      const data = await getInvoices({ contractHistoryId: requestRecordId });
      // 読込中に recordId が変わっていたら結果を捨てる
      if (requestRecordId !== this.recordId) {
        return;
      }
      const nextRows = data || [];
      const visibleIds = new Set(nextRows.map((row) => row.id));
      this.selectedIds = (this.selectedIds || []).filter((id) =>
        visibleIds.has(id)
      );
      this.rows = nextRows.map((row) => ({
        ...row,
        selected: this.selectedIds.includes(row.id),
        statusLabel: row.invoiced
          ? "連携済"
          : row.exported
            ? "消込済"
            : "未処理",
        amountDisplay: row.amount == null ? 0 : row.amount
      }));
    } catch (error) {
      if (requestRecordId !== this.recordId) {
        return;
      }
      this.errorMessage = this.reduceError(error);
      this.rows = [];
      this.selectedIds = [];
    } finally {
      if (requestRecordId === this.recordId) {
        this.isLoading = false;
      }
    }
  }

  handleDateChange(event) {
    this.operationDate = event.detail.value;
  }

  handleToggle(event) {
    const id = event.target.dataset.id;
    const checked = event.target.checked;
    if (checked) {
      if (!this.selectedIds.includes(id)) {
        this.selectedIds = [...this.selectedIds, id];
      }
    } else {
      this.selectedIds = this.selectedIds.filter((value) => value !== id);
    }
    this.rows = this.rows.map((row) => ({
      ...row,
      selected: this.selectedIds.includes(row.id)
    }));
  }

  handleSelectAll(event) {
    const checked = event.target.checked;
    this.selectedIds = checked ? this.rows.map((row) => row.id) : [];
    this.rows = this.rows.map((row) => ({
      ...row,
      selected: checked
    }));
  }

  async handleMarkInvoiced() {
    const invoiceIds = this.actionInvoiceIds;
    await this.runAction(
      () =>
        markInvoiced({
          invoiceIds,
          integrationDate: this.operationDate || null
        }),
      "連携日を設定しました"
    );
  }

  async handleMarkExported() {
    const invoiceIds = this.actionInvoiceIds;
    await this.runAction(
      () =>
        markExported({
          invoiceIds,
          clearingDate: this.operationDate || null
        }),
      "消込日を設定しました"
    );
  }

  async handleClearExport() {
    const invoiceIds = this.actionInvoiceIds;
    await this.runAction(
      () => clearExportDate({ invoiceIds }),
      "消込日をクリアしました"
    );
  }

  async runAction(action, successMessage) {
    if (this.disableActions) {
      return;
    }
    this.isLoading = true;
    this.errorMessage = "";
    try {
      const count = await action();
      this.dispatchEvent(
        new ShowToastEvent({
          title: "完了",
          message: `${successMessage}（${count} 件）`,
          variant: "success"
        })
      );
      this.selectedIds = [];
      await this.loadRows();
    } catch (error) {
      this.errorMessage = this.reduceError(error);
      this.dispatchEvent(
        new ShowToastEvent({
          title: "エラー",
          message: this.errorMessage,
          variant: "error"
        })
      );
    } finally {
      this.isLoading = false;
    }
  }

  reduceError(error) {
    if (!error) {
      return "不明なエラーです。";
    }
    if (Array.isArray(error.body)) {
      return error.body.map((e) => e.message).join(", ");
    }
    if (typeof error.body?.message === "string") {
      return error.body.message;
    }
    return error.message || "処理に失敗しました。";
  }
}
