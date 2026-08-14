import { LightningElement, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getBoardContext from "@salesforce/apex/EstimateOrderBoardController.getBoardContext";
import listEstimates from "@salesforce/apex/EstimateOrderBoardController.listEstimates";
import confirmOrder from "@salesforce/apex/OrderCreateController.confirmOrder";

const TYPE_OPTIONS = [
  { label: "すべて", value: "" },
  { label: "New", value: "New" },
  { label: "Change", value: "Change" },
  { label: "Renew", value: "Renew" },
  { label: "Cancel", value: "Cancel" },
  { label: "Add", value: "Add" }
];

export default class EstimateOrderBoard extends LightningElement {
  @track isLoading = true;
  @track isOrdering = false;
  @track errorMessage = "";
  @track rows = [];
  @track selectedIds = [];
  @track historyType = "";
  @track termStartFrom = null;
  @track termStartTo = null;
  @track searchText = "";
  @track canOrder = false;
  @track selectAllConfirmThreshold = 100;
  @track pendingSelectAll = false;
  @track pendingSelectAllCount = 0;
  @track orderResults = [];
  @track orderProgressLabel = "";

  typeOptions = TYPE_OPTIONS;

  columns = [
    {
      label: "見積名",
      fieldName: "recordUrl",
      type: "url",
      typeAttributes: { label: { fieldName: "historyName" }, target: "_blank" }
    },
    { label: "種別", fieldName: "historyType", type: "text", initialWidth: 90 },
    { label: "取引先", fieldName: "accountName", type: "text" },
    { label: "契約サービス", fieldName: "contractServiceName", type: "text" },
    {
      label: "開始日",
      fieldName: "termStartDate",
      type: "date-local",
      initialWidth: 120
    },
    {
      label: "終了日",
      fieldName: "termEndDate",
      type: "date-local",
      initialWidth: 120
    },
    {
      label: "金額",
      fieldName: "amount",
      type: "currency",
      typeAttributes: { currencyCode: "JPY" },
      initialWidth: 120
    },
    {
      label: "申込日",
      fieldName: "applicationDate",
      type: "date-local",
      initialWidth: 120
    }
  ];

  connectedCallback() {
    this.bootstrap();
  }

  get selectedCount() {
    return this.selectedIds.length;
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  get orderDisabled() {
    return (
      this.canOrder !== true ||
      this.selectedIds.length === 0 ||
      this.isOrdering === true ||
      this.isLoading === true
    );
  }

  get orderButtonLabel() {
    return this.selectedCount > 0
      ? "受注する（" + this.selectedCount + "）"
      : "受注する";
  }

  get failedResults() {
    return this.orderResults.filter((item) => item.success !== true);
  }

  get hasFailedResults() {
    return this.failedResults.length > 0;
  }

  get successCount() {
    return this.orderResults.filter((item) => item.success === true).length;
  }

  async bootstrap() {
    this.isLoading = true;
    this.errorMessage = "";
    try {
      const context = await getBoardContext();
      this.canOrder = context && context.canOrder === true;
      this.selectAllConfirmThreshold =
        context && context.selectAllConfirmThreshold
          ? context.selectAllConfirmThreshold
          : 100;
      await this.loadRows();
    } catch (error) {
      this.errorMessage = this.toMessage(error);
    } finally {
      this.isLoading = false;
    }
  }

  async loadRows() {
    this.isLoading = true;
    this.errorMessage = "";
    this.orderResults = [];
    try {
      const records = await listEstimates({
        historyType: this.historyType || null,
        termStartFrom: this.termStartFrom || null,
        termStartTo: this.termStartTo || null,
        searchText: this.searchText || null
      });
      this.rows = (records || []).map((row) => ({
        ...row,
        recordUrl: "/" + row.contractHistoryId
      }));
      this.selectedIds = [];
    } catch (error) {
      this.errorMessage = this.toMessage(error);
      this.rows = [];
    } finally {
      this.isLoading = false;
    }
  }

  handleTypeChange(event) {
    this.historyType = event.detail.value;
  }

  handleTermStartFromChange(event) {
    this.termStartFrom = event.target.value || null;
  }

  handleTermStartToChange(event) {
    this.termStartTo = event.target.value || null;
  }

  handleSearchChange(event) {
    this.searchText = event.target.value || "";
  }

  handleSearch() {
    this.loadRows();
  }

  handleRowSelection(event) {
    const selected = event.detail.selectedRows || [];
    if (
      selected.length === this.rows.length &&
      this.rows.length > this.selectAllConfirmThreshold &&
      this.pendingSelectAll !== true
    ) {
      this.pendingSelectAll = true;
      this.pendingSelectAllCount = this.rows.length;
      this.selectedIds = [];
      return;
    }
    this.selectedIds = selected.map((row) => row.contractHistoryId);
  }

  handleConfirmSelectAll() {
    this.pendingSelectAll = false;
    this.selectedIds = this.rows.map((row) => row.contractHistoryId);
  }

  handleCancelSelectAll() {
    this.pendingSelectAll = false;
    this.selectedIds = [];
  }

  async handleOrder() {
    if (this.orderDisabled) {
      return;
    }
    const targets = this.rows.filter((row) =>
      this.selectedIds.includes(row.contractHistoryId)
    );
    if (targets.length === 0) {
      return;
    }

    this.isOrdering = true;
    this.orderResults = [];
    this.errorMessage = "";
    let success = 0;
    let failed = 0;

    for (let i = 0; i < targets.length; i += 1) {
      const row = targets[i];
      this.orderProgressLabel =
        "受注中 " + (i + 1) + " / " + targets.length + "（" + row.historyName + "）";
      try {
        await confirmOrder({
          contractHistoryId: row.contractHistoryId,
          billingCustomFieldsJson: null,
          createRenewOpportunity: false,
          expectedLastModifiedToken: null
        });
        success += 1;
        this.orderResults = [
          ...this.orderResults,
          {
            contractHistoryId: row.contractHistoryId,
            historyName: row.historyName,
            success: true,
            message: "受注しました"
          }
        ];
      } catch (error) {
        failed += 1;
        this.orderResults = [
          ...this.orderResults,
          {
            contractHistoryId: row.contractHistoryId,
            historyName: row.historyName,
            success: false,
            message: this.toMessage(error)
          }
        ];
      }
    }

    this.isOrdering = false;
    this.orderProgressLabel = "";
    this.dispatchEvent(
      new ShowToastEvent({
        title: "一括受注",
        message: "成功 " + success + " 件 / 失敗 " + failed + " 件",
        variant: failed === 0 ? "success" : "warning"
      })
    );
    await this.loadRows();
  }

  toMessage(error) {
    if (!error) {
      return "処理に失敗しました。";
    }
    if (typeof error === "string") {
      return error;
    }
    if (error.body && error.body.message) {
      return error.body.message;
    }
    if (Array.isArray(error.body) && error.body[0] && error.body[0].message) {
      return error.body[0].message;
    }
    return error.message || "処理に失敗しました。";
  }
}
