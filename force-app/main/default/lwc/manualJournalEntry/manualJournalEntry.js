import { LightningElement, api, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
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
  completionNote = "";
  /** 仕様: Accounting 第8.5節。登録の要否には使わない。親が渡す請求書Lock。 */
  @api hasLockedJournals = false;
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

  @track settingId = "";
  @track postingDate = "";
  @track amount = "";
  @track registerCancelDate = "";
  @track registerNeedsCancelDateFromDiff = false;
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
    const selected = this.selectedSetting();
    return selected?.description || "";
  }

  selectedSetting() {
    if (!this.settingId) {
      return null;
    }
    return (this.settings || []).find(
      (row) => row.settingId === this.settingId
    );
  }

  // 仕様: Accounting 第10.3節・第11.4節。設定選択後、説明の下・金額の上に読取専用の借方・貸方。
  get showSelectedAccounts() {
    return Boolean(this.settingId);
  }

  get selectedDebitAccountName() {
    return this.selectedSetting()?.debitAccountName || "";
  }

  get selectedCreditAccountName() {
    return this.selectedSetting()?.creditAccountName || "";
  }

  // 仕様: Accounting 第8.5節・第8.8節。この操作のDiff逆仕訳があるときだけ取消基準日。
  get registerRequiresDate() {
    return this.registerNeedsCancelDateFromDiff === true;
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

  get inputsDisabled() {
    return this.disabled || this.busy;
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
        this.manualJournalStatusLabel(header.transactionStatus),
      isCancelOpen: this.cancelHeaderId === header.headerId,
      cancelRowKey: `${header.headerId}-cancel`
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
    if (this.busy) {
      return;
    }
    const field = event.target.dataset.field;
    if (!field) {
      return;
    }
    this[field] = event.detail.value;
  }

  // 仕様: Accounting 第10.3節、第11.4節、第8.8節、Core 第7.9.6節
  // 仕様: Accounting 第8.8節。実行前に件数を出して確認後に実行する。プレビュー中も止める。
  async handleRegister() {
    if (this.busy || this.registerDisabled) {
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
    this.busy = true;
    try {
      await previewRegisterManualJournal({
        invoiceId: this.invoiceId,
        settingId: this.settingId,
        postingDate: this.postingDate,
        amount,
        cancellationDate,
        expectedToken: this.expectedToken,
        contractHistoryId: this.contractHistoryId
      });
    } catch (error) {
      this.busy = false;
      this.dispatchEvent(
        new ShowToastEvent({
          title: "手動仕訳の登録に失敗しました",
          message: this.reduceError(error),
          variant: "error"
        })
      );
      return;
    }
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
      this.registerNeedsCancelDateFromDiff = false;
      this.completionNote = "手動仕訳を登録しました。";
      this.settingId = "";
      this.amount = "";
      this.dispatchEvent(new CustomEvent("complete"));
    } catch (error) {
      const message = this.reduceError(error);
      if (String(message || "").includes("取消基準日が必要")) {
        this.registerNeedsCancelDateFromDiff = true;
        this.seedRegisterCancelDate();
      }
      this.dispatchEvent(
        new ShowToastEvent({
          title: "手動仕訳の登録に失敗しました",
          message,
          variant: "error"
        })
      );
    } finally {
      this.busy = false;
    }
  }

  async handleStartCancel(event) {
    if (this.busy) {
      return;
    }
    this.cancelHeaderId = event.currentTarget.dataset.headerId;
    this.cancelReason = "";
    this.cancelReasonText = "";
    this.cancelRequiresDate = false;
    this.cancelDate = "";
    try {
      const preview = await previewCancelManualJournal({
        headerId: this.cancelHeaderId,
        cancellationDate: null,
        contractHistoryId: this.contractHistoryId
      });
      this.cancelRequiresDate = (preview?.reverseCount || 0) > 0;
      this.cancelDate = this.cancelRequiresDate ? this.todayLocalIso() : "";
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "手動仕訳エラー",
          message: this.reduceError(error),
          variant: "error"
        })
      );
    }
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
    this.busy = true;
    try {
      const preview = await previewCancelManualJournal({
        headerId: this.cancelHeaderId,
        cancellationDate: this.cancelRequiresDate
          ? this.cancelDate || null
          : null,
        contractHistoryId: this.contractHistoryId
      });
      if ((preview?.reverseCount || 0) > 0 && this.cancelRequiresDate !== true) {
        this.cancelRequiresDate = true;
        this.cancelDate = this.todayLocalIso();
        this.busy = false;
        this.dispatchEvent(
          new ShowToastEvent({
            title: "手動仕訳の取消に失敗しました",
            message: "ロック済み仕訳がある取消では取消基準日が必要です。",
            variant: "error"
          })
        );
        return;
      }
    } catch (error) {
      this.busy = false;
      this.dispatchEvent(
        new ShowToastEvent({
          title: "手動仕訳の取消に失敗しました",
          message: this.reduceError(error),
          variant: "error"
        })
      );
      return;
    }
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
      this.completionNote = "手動仕訳を取り消しました。";
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
