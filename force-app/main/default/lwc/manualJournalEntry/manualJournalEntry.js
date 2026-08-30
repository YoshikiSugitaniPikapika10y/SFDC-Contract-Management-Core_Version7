import { LightningElement, api, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import LightningConfirm from "lightning/confirm";
import registerManualJournal from "@salesforce/apex/ManualJournalController.register";
import cancelManualJournal from "@salesforce/apex/ManualJournalController.cancel";
import previewCancelManualJournal from "@salesforce/apex/ManualJournalController.previewCancel";
import previewRegisterManualJournal from "@salesforce/apex/ManualJournalController.previewRegister";
import issueInvoiceOperationKey from "@salesforce/apex/InvoicePreviewOpsController.issueInvoiceOperationKey";

export default class ManualJournalEntry extends LightningElement {
  @api invoiceId;
  @api contractHistoryId;
  @api settings = [];
  @api headers = [];
  @api disabled = false;
  @api expectedToken;
  /** 仕様: 日付仕様 第8章。請求ボード `getInvoicePreview.operationDay`。 */
  @api
  get operationDay() {
    return this._operationDay;
  }
  set operationDay(value) {
    this._operationDay = value;
    if (!this.postingDate) {
      const today = this.todayLocalIso();
      if (today) {
        this.postingDate = today;
      }
    }
    this.seedRegisterCancelDate();
  }

  /** 仕様: Accounting 第8.5節・第8.8節。請求書単位の Active Lock。 */
  @api
  get hasLockedJournals() {
    return this._hasLockedJournals === true;
  }
  set hasLockedJournals(value) {
    this._hasLockedJournals = value === true;
    this.seedRegisterCancelDate();
  }

  @track settingId = "";
  @track postingDate = "";
  @track amount = "";
  @track registerCancelDate = "";
  @track cancelHeaderId = "";
  @track cancelReason = "";
  @track cancelReasonText = "";
  @track cancelDate = "";
  @track cancelRequiresDate = false;
  @track busy = false;
  pendingOperationKey;

  get settingOptions() {
    return (this.settings || []).map((row) => {
      const option = {
        label: row.label || row.settingId,
        value: row.settingId
      };
      if (row.description) {
        option.description = row.description;
      }
      return option;
    });
  }

  // 仕様: Accounting 第10.2節、第11.4節。選択したメニューの説明を確認してから日付・金額を入れる。
  get selectedSettingDescription() {
    if (!this.settingId) {
      return "";
    }
    const selected = (this.settings || []).find(
      (row) => row.settingId === this.settingId
    );
    return selected?.description || "";
  }

  // 仕様: Accounting 第8.5節・第8.8節。ONかつ Active Lock があるときだけ取消基準日。
  get registerRequiresDate() {
    return this.hasLockedJournals === true;
  }

  // 仕様: Accounting 第2.4節・第10.4節、Core 第1.1.10節。「その他」だけ理由テキスト必須。
  isBlankReasonText(value) {
    return value == null || String(value).trim() === "";
  }

  get cancelReasonTextRequired() {
    return this.cancelReason === "Other";
  }

  get cancelConfirmDisabled() {
    return (
      this.busy ||
      !this.cancelReason ||
      (this.cancelReason === "Other" &&
        this.isBlankReasonText(this.cancelReasonText)) ||
      (this.cancelRequiresDate && !this.cancelDate)
    );
  }

  get cancelReasonOptions() {
    return [
      { label: "金額・日付などの誤り", value: "AmountOrDateError" },
      { label: "登録先の誤り", value: "WrongDestination" },
      { label: "重複登録", value: "Duplicate" },
      { label: "元取引の変更・取消", value: "SourceChanged" },
      { label: "その他", value: "Other" }
    ];
  }

  // 仕様: Accounting 第10.3節。0より大きい整数円。小数は登録しない。
  get registerDisabled() {
    const amount = Number(this.amount);
    return (
      this.disabled ||
      this.busy ||
      !this.invoiceId ||
      !this.settingId ||
      !this.postingDate ||
      !this.amount ||
      !Number.isFinite(amount) ||
      amount <= 0 ||
      amount !== Math.trunc(amount) ||
      (this.registerRequiresDate && !this.registerCancelDate)
    );
  }

  get displayHeaders() {
    return (this.headers || []).map((header) => ({
      ...header,
      transactionStatusLabel:
        header.transactionStatusLabel ||
        this.manualJournalStatusLabel(header.transactionStatus)
    }));
  }

  get hasHeaders() {
    return (this.headers || []).length > 0;
  }

  // 仕様: Core 第0.1節、Accounting 第10.3節。保存値は変えない。
  manualJournalStatusLabel(status) {
    if (status === "Active") {
      return "有効";
    }
    if (status === "Cancelled") {
      return "取消済";
    }
    return status || "";
  }

  // 仕様: 日付仕様 第8章。組織タイムゾーンの年月日。ブラウザローカルや toISOString() は使わない。
  todayLocalIso() {
    const value = this.operationDay;
    if (!value) {
      return "";
    }
    return String(value).slice(0, 10);
  }

  seedRegisterCancelDate() {
    if (!this.registerRequiresDate || this.registerCancelDate) {
      return;
    }
    const today = this.todayLocalIso();
    if (today) {
      this.registerCancelDate = today;
    }
  }

  handleFieldChange(event) {
    const field = event.target.dataset.field;
    if (!field) {
      return;
    }
    this[field] = event.detail.value;
  }

  // 仕様: Accounting 第10.3節、第11.4節、第8.8節、Core 第7.9.6節
  async handleRegister() {
    if (this.registerDisabled) {
      return;
    }
    const amount = Number(this.amount);
    // 仕様: Accounting 第10.3節。0より大きい整数円。入金画面と同じ検査。
    if (!Number.isFinite(amount) || amount <= 0 || amount !== Math.trunc(amount)) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "手動仕訳の登録に失敗しました",
          message: "金額は0より大きい整数にしてください。",
          variant: "error"
        })
      );
      return;
    }
    if (this.registerRequiresDate && !this.registerCancelDate) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "手動仕訳の登録に失敗しました",
          message: "ロック済み仕訳がある取消では取消基準日が必要です。",
          variant: "error"
        })
      );
      return;
    }
    const cancellationDate = this.registerRequiresDate
      ? this.registerCancelDate || null
      : null;
    let journalPreviewText = "";
    try {
      const preview = await previewRegisterManualJournal({
        invoiceId: this.invoiceId,
        settingId: this.settingId,
        postingDate: this.postingDate,
        amount,
        cancellationDate,
        expectedToken: this.expectedToken,
        contractHistoryId: this.contractHistoryId
      });
      journalPreviewText = preview?.displayText || "";
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "手動仕訳の登録に失敗しました",
          message: this.reduceError(error),
          variant: "error"
        })
      );
      return;
    }
    const confirmed = await LightningConfirm.open({
      label: "手動仕訳を登録",
      message:
        "この手動仕訳を登録します。よろしいですか？\n\n" + journalPreviewText,
      variant: "header"
    });
    if (!confirmed) {
      return;
    }
    this.busy = true;
    try {
      if (!this.pendingOperationKey) {
        this.pendingOperationKey = await issueInvoiceOperationKey();
      }
      await registerManualJournal({
        invoiceId: this.invoiceId,
        settingId: this.settingId,
        postingDate: this.postingDate,
        amount,
        cancellationDate,
        expectedToken: this.expectedToken,
        businessOperationKey: this.pendingOperationKey,
        contractHistoryId: this.contractHistoryId
      });
      this.pendingOperationKey = null;
      this.dispatchEvent(
        new ShowToastEvent({
          title: "手動仕訳を登録しました",
          message: journalPreviewText,
          variant: "success",
          mode: journalPreviewText ? "sticky" : "dismissable"
        })
      );
      this.settingId = "";
      this.amount = "";
      this.dispatchEvent(new CustomEvent("complete"));
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "手動仕訳の登録に失敗しました",
          message: this.reduceError(error),
          variant: "error"
        })
      );
    } finally {
      this.busy = false;
    }
  }

  handleStartCancel(event) {
    this.cancelHeaderId = event.currentTarget.dataset.headerId;
    this.cancelReason = "";
    this.cancelReasonText = "";
    const header = (this.headers || []).find(
      (row) => row.headerId === this.cancelHeaderId
    );
    // 仕様: Accounting 第10.3節、第10.4節、日付仕様 第7.3節、第8節
    this.cancelRequiresDate = header?.hasLockedJournals === true;
    this.cancelDate = this.cancelRequiresDate ? this.todayLocalIso() : "";
  }

  // 仕様: Core 第7.9.6節、Accounting 第10.4節、第8.5節、日付仕様 第7.3節
  // 仕様: Accounting 第2.4節・第10.4節、Core 第1.1.10節。「その他」だけ理由テキスト必須。
  async handleCancel() {
    if (!this.cancelHeaderId || !this.cancelReason || this.busy) {
      return;
    }
    if (
      this.cancelReason === "Other" &&
      this.isBlankReasonText(this.cancelReasonText)
    ) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "手動仕訳の取消に失敗しました",
          message: "取消理由がその他のときは内容を入力してください。",
          variant: "error"
        })
      );
      return;
    }
    if (this.cancelRequiresDate && !this.cancelDate) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "手動仕訳の取消に失敗しました",
          message: "ロック済み仕訳がある取消では取消基準日が必要です。",
          variant: "error"
        })
      );
      return;
    }
    let journalPreviewText = "";
    try {
      const preview = await previewCancelManualJournal({
        headerId: this.cancelHeaderId,
        cancellationDate: this.cancelRequiresDate
          ? this.cancelDate || null
          : null,
        contractHistoryId: this.contractHistoryId
      });
      journalPreviewText = preview?.displayText || "";
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "手動仕訳の取消に失敗しました",
          message: this.reduceError(error),
          variant: "error"
        })
      );
      return;
    }
    const confirmed = await LightningConfirm.open({
      label: "手動仕訳を取消",
      message:
        "この手動仕訳を取り消します。よろしいですか？\n\n" + journalPreviewText,
      variant: "header"
    });
    if (!confirmed) {
      return;
    }
    this.busy = true;
    try {
      if (!this.pendingOperationKey) {
        this.pendingOperationKey = await issueInvoiceOperationKey();
      }
      await cancelManualJournal({
        headerId: this.cancelHeaderId,
        cancellationReason: this.cancelReason,
        cancellationReasonText: this.cancelReasonText || null,
        cancellationDate: this.cancelRequiresDate
          ? this.cancelDate || null
          : null,
        expectedToken: this.expectedToken,
        businessOperationKey: this.pendingOperationKey,
        contractHistoryId: this.contractHistoryId
      });
      this.pendingOperationKey = null;
      this.dispatchEvent(
        new ShowToastEvent({
          title: "手動仕訳を取り消しました",
          message: journalPreviewText,
          variant: "success",
          mode: journalPreviewText ? "sticky" : "dismissable"
        })
      );
      this.cancelHeaderId = "";
      this.cancelRequiresDate = false;
      this.cancelDate = "";
      this.dispatchEvent(new CustomEvent("complete"));
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "手動仕訳の取消に失敗しました",
          message: this.reduceError(error),
          variant: "error"
        })
      );
    } finally {
      this.busy = false;
    }
  }

  reduceError(error) {
    return (
      error?.body?.message ||
      error?.body?.[0]?.message ||
      error?.message ||
      "処理に失敗しました。"
    );
  }
}
