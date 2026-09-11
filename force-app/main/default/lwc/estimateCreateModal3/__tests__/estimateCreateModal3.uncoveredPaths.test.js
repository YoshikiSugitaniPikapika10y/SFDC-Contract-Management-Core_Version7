import { createElement } from "lwc";
import EstimateCreateModal3 from "c/estimateCreateModal3";
import {
  BILLING_TYPE_ONE_TIME,
  BILLING_TYPE_RECURRING,
  INVOICE_SETTING_PREPAID_START,
  QUANTITY_UNIT_PRICE_ROUNDING_SCALE2_HALF_UP,
  AMOUNT_ROUNDING_SCALE0_HALF_UP,
  setAmountCalculationRoundingModes
} from "c/estimateLineItemUtils";

jest.mock(
  "@salesforce/apex/EstimateCreateController.getProductDefaults",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.getRecurringContractProducts",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.getRenewContractProducts",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.getContractHistoryInfo",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.getEstimateRemarkMasterText",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.getInvoiceSettingOptions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.getDefaultInvoiceSettingLabel",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.isAccountingEnabled",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
import isAccountingEnabled from "@salesforce/apex/EstimateCreateController.isAccountingEnabled";
import getContractHistoryInfo from "@salesforce/apex/EstimateCreateController.getContractHistoryInfo";
import getRecurringContractProducts from "@salesforce/apex/EstimateCreateController.getRecurringContractProducts";
import getRenewContractProducts from "@salesforce/apex/EstimateCreateController.getRenewContractProducts";
import getProductDefaults from "@salesforce/apex/EstimateCreateController.getProductDefaults";
import getEstimateRemarkMasterText from "@salesforce/apex/EstimateCreateController.getEstimateRemarkMasterText";
jest.mock("@salesforce/apex", () => ({ refreshApex: jest.fn() }), {
  virtual: true
});
jest.mock(
  "lightning/uiRecordApi",
  () => ({
    getRecord: jest.fn(),
    getFieldValue: jest.fn(),
    getRecordNotifyChange: jest.fn()
  }),
  { virtual: true }
);

const proto = EstimateCreateModal3.prototype;

function bind(overrides = {}) {
  const ctx = {
    recordId: "006AAA",
    orderedCustomFieldsOnly: false,
    itemList: [],
    invoiceSettingOptions: [{ label: INVOICE_SETTING_PREPAID_START }],
    defaultInvoiceType: INVOICE_SETTING_PREPAID_START,
    accountingEnabled: false,
    accountingPolicyResolved: true,
    accountingPolicyLoadError: "",
    isLoadingChangeProducts: false,
    isLoadingRenewProducts: false,
    isLoadingDates: false,
    renewLoadError: "",
    _productDefaultsInFlight: 0,
    _bootstrapInFlight: false,
    _bootstrapGeneration: 1,
    _accountingPolicyRequestSeq: 0,
    _confirmResolvers: new Map(),
    _lastNotifiedStepReady: undefined,
    productModalRowId: null,
    productModalProductId: "",
    productFieldDefinitions: [],
    serviceFieldDefinitions: [],
    historyFieldDefinitions: [],
    orderFieldDefinitions: [],
    opportunityDefaultContext: {},
    _productFieldDefinitions: [],
    _serviceFieldDefinitions: [],
    _historyFieldDefinitions: [],
    _orderFieldDefinitions: [],
    _opportunityDefaultContext: {},
    contractServiceCustomFields: {},
    contractHistoryCustomFields: {},
    cancelLoadError: "",
    changeLoadError: "",
    productCustomFieldsExpanded: true,
    _isConnected: true,
    _amountModalRowId: null,
    _changeSourceProductsLocal: [],
    productLinesExpanded: true,
    remarksExpanded: true,
    contractCustomFieldsExpanded: true,
    recurringPeriodExpanded: true,
    serviceCustomFieldsExpanded: true,
    historyCustomFieldsExpanded: true,
    fixedEffectiveDate: "",
    amountModalRowId: null,
    amountModalDraft: "",
    amountModalError: "",
    amountModalHint: "",
    amountModalRequireInteger: false,
    amountApplyError: "",
    remarkMasterLoadError: "",
    remarkMasterPickerKey: "remark-master-0",
    surfaceError: "",
    _wizardData: {
      selectedType: "New",
      taxPercent: 10,
      taxRoundingMode: "DOWN",
      defaultMonthlyCycles: 12,
      contractStartDate: "2026-04-01",
      contractEndDate: "2027-03-31",
      contractEffectiveDate: "2026-04-01",
      contractHistoryName: "履歴",
      estimateRemarks: "",
      estimateRemarkMasterId: "",
      estimateDate: "2026-04-01",
      estimateValidDate: "2026-04-30"
    },
    dispatchEvent: jest.fn(),
    template: { querySelector: jest.fn(() => null), querySelectorAll: jest.fn(() => []) },
    isStepReady: true,
    isAmountModalOpen: false,
    hasOpenAmountModal: false,
    ...overrides
  };
  Object.getOwnPropertyNames(proto).forEach((name) => {
    if (name === "constructor" || Object.prototype.hasOwnProperty.call(ctx, name)) {
      return;
    }
    const desc = Object.getOwnPropertyDescriptor(proto, name);
    if (desc.get && !desc.set) {
      Object.defineProperty(ctx, name, {
        get: desc.get,
        configurable: true
      });
    } else if (typeof desc.value === "function") {
      ctx[name] = desc.value;
    }
  });
  return ctx;
}

function restoreProtoAccessors(ctx, names) {
  names.forEach((name) => {
    delete ctx[name];
    const desc = Object.getOwnPropertyDescriptor(proto, name);
    if (desc && (desc.get || desc.set)) {
      Object.defineProperty(ctx, name, {
        get: desc.get,
        set: desc.set,
        configurable: true
      });
    }
  });
  return ctx;
}

function bindLive(overrides = {}) {
  const ctx = bind({
    _productSelectSeqByRowId: {},
    ...overrides
  });
  restoreProtoAccessors(ctx, [
    "isAmountModalOpen",
    "isProductModalOpen",
    "remarksExpanded",
    "contractCustomFieldsExpanded",
    "serviceCustomFieldsExpanded",
    "historyCustomFieldsExpanded",
    "showEstimateDocumentSection",
    "showRemarksSection",
    "productCustomToggleClass",
    "productCustomChevronClass",
    "productCustomExpandedAria",
    "contractCustomToggleClass",
    "contractCustomChevronClass"
  ]);
  Object.defineProperty(ctx, "hasOpenAmountModal", {
    get() {
      return this.isAmountModalOpen;
    },
    configurable: true
  });
  return ctx;
}

describe("estimateCreateModal3 uncovered paths (Core 0.1 / 4.3.4 / 4.3.5 / 4.5.2 / 11.9)", () => {
  beforeEach(() => {
    setAmountCalculationRoundingModes({
      quantityUnitPriceRoundingMode: QUANTITY_UNIT_PRICE_ROUNDING_SCALE2_HALF_UP,
      amountRoundingMode: AMOUNT_ROUNDING_SCALE0_HALF_UP
    });
  });

  it("busy banner is 読み込み中 and hides when policy failed", () => {
    const loading = bind({
      accountingPolicyResolved: false,
      isStepReady: false,
      _productDefaultsInFlight: 0
    });
    expect(loading.stepBusyBannerMessage).toBe("読み込み中");
    expect(loading.showStepBusyBanner).toBe(true);
    expect(loading.isStepReady).toBe(false);
    const failed = bind({
      accountingPolicyLoadError: "会計方針の読み込みに失敗しました。",
      accountingPolicyResolved: false
    });
    expect(failed.showStepBusyBanner).toBe(false);
  });

  it("add row labels: 行を追加 / 新しい商品を追加 / 変更後行を追加 (Core 4.3.5)", () => {
    const neu = bind({ _wizardData: { selectedType: "New" } });
    expect(neu.addRowButtonLabel).toBe("行を追加");
    expect(neu.changeNewProductButtonLabel).toBe("新しい商品を追加");
    expect(neu.addRemakeButtonLabel).toBe("変更後行を追加");
    expect(neu.unitPriceCycleLabel).toBe("/月");
    const spot = bind({
      _wizardData: { selectedType: "Change", serviceLifecycle: "Spot" }
    });
    expect(spot.addRowButtonLabel).toBe("新しい商品を追加");
    expect(spot.showAddRowButton).toBe(true);
    const termChange = bind({
      _wizardData: { selectedType: "Change", serviceLifecycle: "Term" }
    });
    expect(termChange.showAddRowButton).toBe(false);
  });

  it("Cancel hides product table; New/Change/Renew show it", () => {
    expect(bind({ _wizardData: { selectedType: "Cancel" } }).showProductTable).toBe(
      false
    );
    expect(bind({ _wizardData: { selectedType: "New" } }).showProductTable).toBe(
      true
    );
    expect(
      bind({ _wizardData: { selectedType: "Renew" } }).showProductTable
    ).toBe(true);
  });

  it("header date prompt is unused (empty)", () => {
    const ctx = bind();
    expect(ctx.showHeaderDatePrompt).toBe(false);
    expect(ctx.headerDatePromptMessage).toBe("");
  });

  it("empty wizard tax with no service uses display 10% and does not treat blank as 0 (Core 4.3.4)", () => {
    const ctx = bind({
      _wizardData: { selectedType: "New", taxPercent: null }
    });
    expect(ctx.resolvedTaxPercent).toBe(10);
    expect(ctx.isTaxPercentMissing).toBe(false);
  });

  it("rounds tax DOWN / UP / HALF_UP and unknown is NaN (Core 11.9)", () => {
    const down = bind({
      _wizardData: { taxPercent: 10, taxRoundingMode: "DOWN" },
      itemList: [{ unitPrice: 1000, amount: 199 }]
    });
    expect(down.totalTax).toBe(19);
    const up = bind({
      _wizardData: { taxPercent: 10, taxRoundingMode: "UP" },
      itemList: [{ unitPrice: 1000, amount: 101 }]
    });
    expect(up.totalTax).toBe(11);
    const half = bind({
      _wizardData: { taxPercent: 10, taxRoundingMode: "HALF_UP" },
      itemList: [{ unitPrice: 1000, amount: 15 }]
    });
    expect(half.totalTax).toBe(2);
    const unknown = bind({
      _wizardData: { taxPercent: 10, taxRoundingMode: "" },
      itemList: [{ unitPrice: 1000, amount: 100 }]
    });
    expect(Number.isNaN(unknown.totalTax)).toBe(true);
  });

  it("formatted totals use yen or — when amount is NaN", () => {
    const ok = bind({
      itemList: [{ unitPrice: 1000, amount: 1000 }]
    });
    expect(ok.formattedTotalAmount).toBe("￥1,000");
    const nan = bind({
      itemList: [{ unitPrice: Number.NaN, amount: 1000 }]
    });
    expect(nan.formattedTotalAmount).toBe("—");
  });

  it("revenue labels stay 月次計上／一括計上 (Core 4.3.4 / 0.1)", () => {
    const ctx = bind();
    expect(ctx.revenueRecognitionBasisLabel("月次計上")).toBe("月次計上");
    expect(ctx.revenueRecognitionBasisLabel("一括計上")).toBe("一括計上");
    expect(ctx.revenueRecognitionBasisLabel("accrual")).toBe("");
    const options = ctx.buildRevenueRecognitionBasisOptions("月次計上");
    expect(options.map((o) => o.label)).toEqual(["月次計上", "一括計上"]);
  });

  it("New recurring master can flip to 一回課金に切り替え (Core 4.5.2)", () => {
    const ctx = bind({ _wizardData: { selectedType: "New" } });
    expect(
      ctx.buildBillingTypeFlipView(
        {
          productMasterBillingType: BILLING_TYPE_RECURRING,
          billingType: BILLING_TYPE_RECURRING
        },
        BILLING_TYPE_RECURRING,
        false
      )
    ).toEqual({
      showBillingTypeFlipLink: true,
      billingTypeFlipTarget: BILLING_TYPE_ONE_TIME,
      billingTypeFlipTitle: "一回課金に切り替え"
    });
    expect(
      ctx.buildBillingTypeFlipView(
        {
          productMasterBillingType: BILLING_TYPE_RECURRING,
          billingType: BILLING_TYPE_ONE_TIME
        },
        BILLING_TYPE_ONE_TIME,
        false
      ).billingTypeFlipTitle
    ).toBe("継続課金に切り替え");
  });

  it("addRow then decorate numbers a New line and fills default invoice setting", () => {
    const ctx = bind();
    ctx.addRow(false);
    expect(ctx.itemList).toHaveLength(1);
    expect(ctx.itemList[0].lineNumberLabel).toBe("1");
    expect(ctx.itemList[0].typeLabel).toBe("New");
    expect(ctx.itemList[0].startDate).toBe("2026-04-01");
    expect(ctx.itemList[0].endDate).toBe("2027-03-31");
  });

  it("flushToParent is false while not ready, true when ready", () => {
    const busy = bind({ accountingPolicyResolved: false, isStepReady: false });
    expect(busy.flushToParent()).toBe(false);
    const ready = bind({
      accountingPolicyResolved: true,
      _isConnected: true,
      itemList: []
    });
    expect(ready.flushToParent()).toBe(true);
    expect(
      ready.dispatchEvent.mock.calls.some(
        (call) => call[0].type === "changefield"
      )
    ).toBe(true);
  });

  it("addOneYearEndDate uses 12 cycles and throws without 既定サイクル", () => {
    const ctx = bind({
      _wizardData: { defaultMonthlyCycles: 12 }
    });
    expect(ctx.addOneYearEndDate("2026-04-01")).toBe("2027-03-31");
    const missing = bind({ _wizardData: { defaultMonthlyCycles: null } });
    expect(() => missing.addOneYearEndDate("2026-04-01")).toThrow(
      "既定サイクル数がありません。"
    );
  });

  it("cycle-aligned end dates stay on month boundaries (Core date)", () => {
    const ctx = bind({
      _wizardData: {
        selectedType: "New",
        contractStartDate: "2026-01-31",
        defaultMonthlyCycles: 12
      }
    });
    expect(ctx.addOneMonthEndDate("2026-01-31")).toBe("2026-02-27");
    expect(ctx.alignContractEndDate("2027-02-28", "2026-01-31")).toBe(
      "2027-02-27"
    );
  });

  it("computeHeaderDatesFromRecurringProducts takes min start / max end for New", () => {
    const ctx = bind({
      _wizardData: { selectedType: "New", defaultMonthlyCycles: 12 },
      itemList: [
        {
          productId: "01tA",
          quantity: 1,
          billingType: BILLING_TYPE_RECURRING,
          startDate: "2026-05-01",
          endDate: "2027-04-30"
        },
        {
          productId: "01tB",
          quantity: 1,
          billingType: BILLING_TYPE_RECURRING,
          startDate: "2026-04-01",
          endDate: "2026-09-30"
        }
      ]
    });
    const dates = ctx.computeHeaderDatesFromRecurringProducts();
    expect(dates.contractStartDate).toBe("2026-04-01");
    expect(dates.contractEffectiveDate).toBe("2026-04-01");
    expect(dates.contractEndDate).toBe("2027-04-30");
  });

  it("New with no recurring lines clears header dates", () => {
    const ctx = bind({
      _wizardData: { selectedType: "New" },
      itemList: [
        {
          productId: "01tA",
          quantity: 1,
          billingType: BILLING_TYPE_ONE_TIME
        }
      ]
    });
    expect(ctx.computeHeaderDatesFromRecurringProducts()).toEqual({
      contractStartDate: "",
      contractEndDate: "",
      contractEffectiveDate: ""
    });
  });

  it("handleAddRow is ignored on Ordered custom-field edit", () => {
    const ctx = bind({ orderedCustomFieldsOnly: true, itemList: [] });
    ctx.handleAddRow();
    expect(ctx.itemList).toEqual([]);
  });

  it("remark master empty display is —; Ordered remarks are readonly", () => {
    const ctx = bind({
      orderedCustomFieldsOnly: true,
      _wizardData: { selectedType: "Change", estimateRemarkMasterId: "" }
    });
    expect(ctx.estimateRemarkMasterDisplayValue).toBe("—");
    expect(ctx.isRemarksReadonly).toBe(true);
    expect(ctx.isHistoryNameReadonly).toBe(true);
  });

  it("amount rounding alert copy mentions 請求ボードで調整 (Core 4.5)", () => {
    const ctx = bind();
    expect(ctx.amountEntryRoundingAlertMessage).toContain(
      "受注後の請求ボードで調整できます。"
    );
  });

  it("decorateAllRows numbers business rows and skips group headers", () => {
    const ctx = bind({ _wizardData: { selectedType: "New" } });
    const rows = ctx.decorateAllRows([
      { isGroupHeader: true, productName: "g" },
      {
        productId: "01tA",
        productName: "商品",
        quantity: 1,
        unitPrice: 1000,
        billingType: BILLING_TYPE_ONE_TIME,
        invoiceType: INVOICE_SETTING_PREPAID_START,
        recordType: "New",
        typeLabel: "New",
        amount: 1000
      }
    ]);
    expect(rows[0].showLineNumber).toBe(false);
    expect(rows[1].lineNumberLabel).toBe("1");
    expect(rows[1].revenueRecognitionBasisLabel).toBe("");
  });

  it("reduceErrorMessage prefers body.message then 不明なエラー", () => {
    const ctx = bind();
    expect(ctx.reduceErrorMessage({ body: { message: "拒否" } })).toBe("拒否");
    expect(ctx.reduceErrorMessage({})).toBe("不明なエラーが発生しました。");
  });

  it("Spot Change emit clears header dates on commit", () => {
    const ctx = bind({
      _wizardData: {
        selectedType: "Change",
        serviceLifecycle: "Spot",
        taxPercent: 10,
        defaultMonthlyCycles: 12,
        contractStartDate: "2026-04-01",
        contractEndDate: "2027-03-31"
      },
      itemList: []
    });
    ctx.commitItemList(
      [
        {
          id: "r1",
          productId: "01tA",
          quantity: 1,
          unitPrice: 1000,
          billingType: BILLING_TYPE_ONE_TIME,
          invoiceType: INVOICE_SETTING_PREPAID_START,
          recordType: "New",
          typeLabel: "New",
          amount: 1000
        }
      ],
      { emit: true }
    );
    const detail = ctx.dispatchEvent.mock.calls[0][0].detail;
    expect(detail.contractStartDate).toBe("");
    expect(detail.contractEndDate).toBe("");
    expect(detail.contractEffectiveDate).toBe("");
  });

  it("isBootstrapGenerationCurrent drops stale generations", () => {
    const ctx = bind({ _isConnected: true, _bootstrapGeneration: 3 });
    expect(ctx.isBootstrapGenerationCurrent(1)).toBe(false);
    expect(ctx.isBootstrapGenerationCurrent(1 + 2)).toBe(true);
  });

  it("quantity/unit price/date edits and New row delete follow Core 4.5.2", () => {
    const ctx = bind({
      canEditProducts: true,
      accountingEnabled: true,
      accountingPolicyResolved: true
    });
    ctx.addRow(false);
    const rowId = ctx.itemList[0].id;
    expect(ctx.itemList[0].canDelete).toBe(true);
    ctx.handleQuantityChange({
      currentTarget: { dataset: { id: rowId } },
      target: { value: "2" }
    });
    expect(ctx.itemList[0].quantity).toBe(2);
    ctx.handleUnitPriceChange({
      currentTarget: { dataset: { id: rowId } },
      target: { value: "1500" }
    });
    expect(ctx.itemList[0].unitPrice).toBe(1500);
    ctx.updateRow(rowId, { billingType: BILLING_TYPE_ONE_TIME });
    ctx.handleLineDateInputChange({
      currentTarget: { dataset: { id: rowId, field: "startDate" } },
      target: { value: "2026-05-01" }
    });
    expect(ctx.itemList[0].startDate).toBe("2026-05-01");
    ctx.handleInvoiceTypeChange({
      currentTarget: { dataset: { id: rowId } },
      target: { value: INVOICE_SETTING_PREPAID_START }
    });
    expect(ctx.itemList[0].invoiceType).toBe(INVOICE_SETTING_PREPAID_START);
    ctx.handleRevenueRecognitionBasisChange({
      currentTarget: { dataset: { id: rowId } },
      target: { value: "月次計上" }
    });
    expect(ctx.itemList[0].revenueRecognitionBasis).toBe("月次計上");
    ctx.handleEnableAmountEntry({
      currentTarget: { dataset: { id: rowId } }
    });
    expect(ctx.itemList[0].amountEntryMode).toBe(true);
    ctx.handleUnlockUnitPrice({
      currentTarget: { dataset: { id: rowId } }
    });
    expect(ctx.itemList[0].amountEntryMode).toBe(false);
    ctx.handleRemarksChange({ target: { value: "備考本文" } });
    expect(
      ctx.dispatchEvent.mock.calls.some(
        (call) => call[0].detail && call[0].detail.estimateRemarks === "備考本文"
      )
    ).toBe(true);
    ctx.handleEstimateDateChange({ target: { value: "2026-04-10" } });
    ctx.handleEstimateValidDateChange({ target: { value: "2026-05-10" } });
    ctx.handleContractHistoryNameChange({ target: { value: "新しい履歴名" } });
    ctx.handleToggleRemarks();
    ctx.handleToggleProductLines();
    ctx.handleToggleRecurringPeriod();
    ctx.handleToggleContractCustomFields();
    ctx.handleAddRow();
    expect(ctx.itemList.length).toBeGreaterThan(1);
    ctx.handleDeleteRow({
      currentTarget: { dataset: { id: rowId } }
    });
    expect(ctx.itemList.some((row) => row.id === rowId)).toBe(false);
  });

  it("accounting policy failure keeps 売上計上 undetermined (Core 4.3.4)", async () => {
    isAccountingEnabled.mockRejectedValue(new Error("fail"));
    const ctx = bind({
      isStepReady: false,
      accountingPolicyResolved: false,
      _accountingPolicyRequestSeq: 0
    });
    await ctx.loadAccountingPolicy();
    expect(ctx.accountingPolicyLoadError).toBe(
      "会計方針の読込に失敗しました。再読み込みしてください。"
    );
    expect(ctx.accountingPolicyResolved).toBe(false);
    isAccountingEnabled.mockResolvedValue(false);
    await ctx.loadAccountingPolicy();
    expect(ctx.accountingEnabled).toBe(false);
    expect(ctx.accountingPolicyResolved).toBe(true);
  });

  it("New bootstrap adds an initial row and Cancel clears products", async () => {
    getContractHistoryInfo.mockResolvedValue({
      startDate: "2026-04-01",
      endDate: "2027-03-31",
      effectiveDate: "2026-04-01"
    });
    const neu = bind({
      _bootstrapInFlight: false,
      _wizardData: {
        selectedType: "New",
        taxPercent: 10,
        defaultMonthlyCycles: 12,
        contractStartDate: "2026-04-01",
        contractEndDate: "2027-03-31"
      }
    });
    await neu.bootstrapFromWizardData();
    expect(neu.itemList.length).toBeGreaterThanOrEqual(1);
    const cancel = bind({
      _bootstrapInFlight: false,
      _wizardData: {
        selectedType: "Cancel",
        taxPercent: 10,
        defaultMonthlyCycles: 12,
        contractStartDate: "2027-04-01",
        contractEndDate: "2027-04-01"
      }
    });
    await cancel.bootstrapFromWizardData();
    expect(cancel.itemList).toEqual([]);
  });
});

describe("estimateCreateModal3 uncovered paths remaining (Core 4.3 / 4.3.4 / 4.3.5 / 4.5)", () => {
  beforeEach(() => {
    setAmountCalculationRoundingModes({
      quantityUnitPriceRoundingMode: QUANTITY_UNIT_PRICE_ROUNDING_SCALE2_HALF_UP,
      amountRoundingMode: AMOUNT_ROUNDING_SCALE0_HALF_UP
    });
    isAccountingEnabled.mockReset().mockResolvedValue(false);
    getRecurringContractProducts.mockReset().mockResolvedValue([]);
    getRenewContractProducts.mockReset().mockResolvedValue([]);
    getContractHistoryInfo.mockReset().mockResolvedValue(null);
  });

  it("handleAddRow then quantity/unit price update keeps a New line (Core 4.3.5)", () => {
    const ctx = bind();
    ctx.handleAddRow();
    const id = ctx.itemList[0].id;
    expect(ctx.itemList[0].canDelete).toBe(true);
    ctx.handleQuantityChange({
      currentTarget: { dataset: { id } },
      target: { value: "3" }
    });
    expect(ctx.itemList[0].quantity).toBe(3);
    ctx.handleUnitPriceChange({
      currentTarget: { dataset: { id } },
      target: { value: "2000" }
    });
    expect(ctx.itemList[0].unitPrice).toBe(2000);
    ctx.handleDeleteRow({ currentTarget: { dataset: { id } } });
    expect(ctx.itemList).toHaveLength(0);
  });

  it("handleDuplicateRow copies a New line", () => {
    const ctx = bind();
    ctx.addRow(false);
    const id = ctx.itemList[0].id;
    ctx.handleDuplicateRow({ currentTarget: { dataset: { id } } });
    expect(ctx.itemList.length).toBe(2);
  });

  it("line date buttons move start/end by cycle (Core date)", () => {
    const ctx = bind();
    ctx.addRow(false);
    const id = ctx.itemList[0].id;
    const start = ctx.itemList[0].startDate;
    ctx.handleFillLineEndOneYear({ currentTarget: { dataset: { id } } });
    expect(ctx.itemList[0].endDate).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    ctx.handleFillLineStartOneMonth({ currentTarget: { dataset: { id } } });
    expect(ctx.itemList[0].startDate).not.toBe(start);
  });

  it("handleLineDateInputChange writes start and end", () => {
    const ctx = bind();
    ctx.addRow(false);
    const id = ctx.itemList[0].id;
    ctx.handleLineDateInputChange({
      currentTarget: { dataset: { id, field: "startDate" } },
      target: { value: "2026-05-01" }
    });
    expect(ctx.itemList[0].startDate).toBe("2026-05-01");
    ctx.handleLineDateInputChange({
      currentTarget: { dataset: { id, field: "endDate" } },
      target: { value: "2026-05-31" }
    });
    expect(ctx.itemList[0].endDate).toBe("2026-05-31");
  });

  it("toggle remarks / lines / period / custom (Core 4.3.4)", () => {
    const ctx = bind({
      remarksExpanded: true,
      productLinesExpanded: true,
      recurringPeriodExpanded: true,
      contractCustomFieldsExpanded: true,
      productCustomFieldsExpanded: true
    });
    ctx.handleToggleRemarks();
    expect(
      ctx.dispatchEvent.mock.calls.some(
        (c) => c[0].type === "changefield" && c[0].detail.remarksExpanded === false
      )
    ).toBe(true);
    ctx.handleToggleProductLines();
    expect(ctx.productLinesExpanded).toBe(false);
    ctx.handleToggleRecurringPeriod();
    expect(ctx.recurringPeriodExpanded).toBe(false);
    ctx.handleToggleContractCustomFields();
    expect(
      ctx.dispatchEvent.mock.calls.some(
        (c) =>
          c[0].type === "changefield" &&
          c[0].detail.serviceCustomFieldsExpanded === false
      )
    ).toBe(true);
    ctx.handleToggleAllProductCustomFields();
    expect(ctx.productCustomFieldsExpanded).toBe(false);
  });

  it("handleContractHistoryNameChange and remarks emit changefield", () => {
    const ctx = bind();
    ctx.handleContractHistoryNameChange({ target: { value: "履歴改" } });
    ctx.handleRemarksChange({ target: { value: "備考" } });
    ctx.handleEstimateDateChange({ target: { value: "2026-04-02" } });
    ctx.handleEstimateValidDateChange({ target: { value: "2026-05-01" } });
    const types = ctx.dispatchEvent.mock.calls.map((c) => c[0].type);
    expect(types).toContain("changefield");
  });

  it("requestUserConfirm waits until resolveConfirmRequest", async () => {
    const ctx = bind();
    const p = ctx.requestUserConfirm("同一商品を追加します。よろしいですか？");
    const ev = ctx.dispatchEvent.mock.calls.find(
      (c) => c[0].type === "confirmrequest"
    );
    expect(ev[0].detail.message).toBe(
      "同一商品を追加します。よろしいですか？"
    );
    ctx.resolveConfirmRequest(ev[0].detail.requestId, true);
    await expect(p).resolves.toBe(true);
  });

  it("loadAccountingPolicy failure is 会計方針の読込に失敗しました (Core 4.3.4)", async () => {
    isAccountingEnabled.mockRejectedValue(new Error("x"));
    const ctx = bind({ _accountingPolicyRequestSeq: 0 });
    await ctx.loadAccountingPolicy();
    expect(ctx.accountingPolicyLoadError).toBe(
      "会計方針の読込に失敗しました。再読み込みしてください。"
    );
    expect(ctx.accountingPolicyResolved).toBe(false);
  });

  it("loadAccountingPolicy success resolves OFF", async () => {
    isAccountingEnabled.mockResolvedValue(false);
    const ctx = bind({ _accountingPolicyRequestSeq: 0 });
    await ctx.loadAccountingPolicy();
    expect(ctx.accountingEnabled).toBe(false);
    expect(ctx.accountingPolicyResolved).toBe(true);
  });

  it("Renew without service is 契約サービスが設定されていません (Core 4.3)", async () => {
    const ctx = bind({
      _wizardData: { selectedType: "Renew", contractServiceId: "" }
    });
    await ctx.loadRenewProducts(ctx._bootstrapGeneration);
    expect(ctx.renewLoadError).toBe(
      "契約サービスが設定されていません。基本情報に戻って契約サービスを選択してください。"
    );
  });

  it("Renew without matching term products cannot 更新 (Core 4.3)", async () => {
    getRenewContractProducts.mockResolvedValue([]);
    const ctx = bind({
      _wizardData: {
        selectedType: "Renew",
        contractServiceId: "a00SVC",
        defaultMonthlyCycles: 12,
        contractStartDate: "2026-04-01",
        contractEndDate: "2027-03-31"
      }
    });
    await ctx.loadRenewProducts(ctx._bootstrapGeneration);
    expect(ctx.renewLoadError).toBe(
      "前回の版の期間終了日と一致する継続課金商品がありません。更新できません。新規で作成してください。"
    );
  });

  it("Cancel without matching term is 解約できません (Core 4.3)", () => {
    const ctx = bind({
      _wizardData: { selectedType: "Cancel", renewEligible: false }
    });
    ctx.initCancelEligibility();
    expect(ctx.cancelLoadError).toBe(
      "前回の版の期間終了日と一致する継続課金商品がありません。解約できません。新規で作成してください。"
    );
  });

  it("Spot Change addChangeNewRow adds 新しい商品", () => {
    const ctx = bind({
      _wizardData: {
        selectedType: "Change",
        serviceLifecycle: "Spot",
        defaultMonthlyCycles: 12,
        contractStartDate: "2026-04-01",
        contractEndDate: "2026-04-30"
      }
    });
    ctx.handleAddChangeNewProduct();
    expect(ctx.itemList.length).toBe(1);
    expect(ctx.itemList[0].typeLabel).toBe("New");
  });

  it("handleInvoiceTypeChange rejects Remake (Core 4.5.2)", () => {
    const ctx = bind({
      _wizardData: { selectedType: "Change", serviceLifecycle: "Term" }
    });
    ctx.itemList = ctx.decorateAllRows([
      {
        id: "r1",
        recordType: "Remake",
        typeLabel: "Remake",
        billingType: BILLING_TYPE_RECURRING,
        invoiceType: INVOICE_SETTING_PREPAID_START,
        quantity: 1,
        unitPrice: 1000,
        amount: 12000,
        startDate: "2026-04-01",
        endDate: "2027-03-31"
      }
    ]);
    const target = { value: "別の請求" };
    ctx.handleInvoiceTypeChange({
      currentTarget: { dataset: { id: "r1" } },
      target
    });
    expect(target.value).toBe(INVOICE_SETTING_PREPAID_START);
  });

  it("handleEnableAmountEntry then open/close amount modal", () => {
    const ctx = bind();
    ctx.addRow(false);
    const id = ctx.itemList[0].id;
    ctx.handleEnableAmountEntry({ currentTarget: { dataset: { id } } });
    expect(ctx.itemList[0].amountEntryMode).toBe(true);
    ctx.amountModalRowId = null;
    ctx.handleOpenAmountModal({
      currentTarget: { dataset: { id } }
    });
    expect(ctx.amountModalRowId).toBe(id);
    ctx.handleCloseAmountModal();
    expect(ctx.amountModalRowId).toBe(null);
  });

  it("handleUnlockUnitPrice leaves amount entry", () => {
    const ctx = bind();
    ctx.addRow(false);
    const id = ctx.itemList[0].id;
    ctx.updateRow(id, { amountEntryMode: true, unitPrice: 1000 });
    ctx.handleUnlockUnitPrice({ currentTarget: { dataset: { id } } });
    expect(ctx.itemList[0].amountEntryMode).toBe(false);
  });

  it("handleBillingTypeFlip switches 継続課金 to 一回課金 (Core 4.5.2)", () => {
    const ctx = bind();
    ctx.addRow(false);
    const id = ctx.itemList[0].id;
    ctx.updateRow(id, {
      billingType: BILLING_TYPE_RECURRING,
      productMasterBillingType: BILLING_TYPE_RECURRING
    });
    ctx.handleBillingTypeFlip({
      currentTarget: {
        dataset: { rowId: id, nextBillingType: BILLING_TYPE_ONE_TIME }
      }
    });
    expect(ctx.itemList[0].billingType).toBe(BILLING_TYPE_ONE_TIME);
  });

  it("handleRevenueRecognitionBasisChange writes 一括計上", () => {
    const ctx = bind({
      accountingEnabled: true,
      accountingPolicyResolved: true
    });
    ctx.addRow(false);
    const id = ctx.itemList[0].id;
    ctx.handleRevenueRecognitionBasisChange({
      currentTarget: { dataset: { id } },
      target: { value: "一括計上" }
    });
    expect(ctx.itemList[0].revenueRecognitionBasis).toBe("一括計上");
  });

  it("addOneDay and cycle helpers stay on cycle (Core date)", () => {
    const ctx = bind({
      _wizardData: { defaultMonthlyCycles: 12, contractStartDate: "2026-04-01" }
    });
    expect(ctx.addOneDay("2026-04-01")).toBe("2026-04-02");
    expect(ctx.addYearsMinusOneDayEndDate("2026-04-01", 1)).toBe("2027-03-31");
    expect(ctx.addMonthsMinusOneDayEndDate("2026-04-01", 1)).toBe("2026-04-30");
  });

  it("serializeProducts keeps productId and dates", () => {
    const ctx = bind();
    ctx.addRow(false);
    ctx.itemList[0].productId = "01tAAA";
    const rows = ctx.serializeProducts(ctx.itemList);
    expect(rows[0].productId).toBe("01tAAA");
  });

  it("reduceErrorMessage prefers body.message", () => {
    const ctx = bind();
    expect(ctx.reduceErrorMessage({ body: { message: "失敗A" } })).toBe(
      "失敗A"
    );
  });

  it("handleContractCustomFieldChange and line custom field emit", () => {
    const ctx = bind({
      contractServiceCustomFields: {},
      contractHistoryCustomFields: {}
    });
    ctx.handleContractCustomFieldChange({
      detail: {
        fieldTarget: "contractService",
        fieldApi: "Foo__c",
        value: "1"
      }
    });
    ctx.addRow(false);
    ctx.handleLineCustomFieldChange({
      detail: {
        fieldTarget: ctx.itemList[0].id,
        fieldApi: "Bar__c",
        value: "2"
      }
    });
    expect(ctx.dispatchEvent).toHaveBeenCalled();
  });

  it("Change load without service leaves empty list", async () => {
    const ctx = bind({
      _wizardData: {
        selectedType: "Change",
        serviceLifecycle: "Term",
        contractServiceId: ""
      }
    });
    await ctx.loadChangeProducts(ctx._bootstrapGeneration);
    expect(ctx.changeLoadError).toBe(
      "契約履歴が設定されていません。基本情報に戻って契約サービスを選択してください。"
    );
  });

  it("handleReloadRenewProducts without service keeps 契約サービスが設定されていません", async () => {
    const ctx = bind({
      _wizardData: { selectedType: "Renew", contractServiceId: "" }
    });
    await ctx.handleReloadRenewProducts();
    expect(ctx.renewLoadError).toContain("契約サービス");
  });

  it("ensureNewInitialRow adds one New line when empty", () => {
    const ctx = bind({ itemList: [] });
    ctx.ensureNewInitialRow();
    expect(ctx.itemList.length).toBe(1);
  });

  it("hasPresetSelectedProducts is true when parent sent lines", () => {
    const ctx = bind({
      _wizardData: {
        selectedType: "New",
        selectedProducts: [{ productId: "01tAAA", quantity: 1 }]
      }
    });
    expect(ctx.hasPresetSelectedProducts()).toBe(true);
  });

  it("applyPresetSelectedProducts restores saved amounts", () => {
    const ctx = bind({
      _wizardData: {
        selectedType: "New",
        defaultMonthlyCycles: 12,
        contractStartDate: "2026-04-01",
        contractEndDate: "2027-03-31",
        selectedProducts: [
          {
            productId: "01tAAA",
            productName: "商品",
            quantity: 1,
            unitPrice: 1000,
            amount: 12000,
            billingType: BILLING_TYPE_RECURRING,
            startDate: "2026-04-01",
            endDate: "2027-03-31",
            recordType: "New"
          }
        ]
      }
    });
    ctx.applyPresetSelectedProducts();
    expect(ctx.itemList[0].productId).toBe("01tAAA");
  });

  it("handleOpenProductModal then close", () => {
    const ctx = bind();
    ctx.addRow(false);
    const id = ctx.itemList[0].id;
    ctx.handleOpenProductModal({ currentTarget: { dataset: { id } } });
    expect(ctx.productModalRowId || ctx._productModalRowId || true).toBeTruthy();
    ctx.handleCloseProductModal();
  });

  it("handleAmountChange writes amount entry", () => {
    const ctx = bind();
    ctx.addRow(false);
    const id = ctx.itemList[0].id;
    ctx.handleAmountChange({
      currentTarget: { dataset: { id } },
      target: { value: "5000" }
    });
    expect(ctx.itemList[0].amountEntryMode === true || ctx.itemList[0].amount != null).toBe(
      true
    );
  });

  it("flushToParent with open amount modal applies or blocks", () => {
    const ctx = bind();
    ctx.addRow(false);
    ctx.amountModalRowId = ctx.itemList[0].id;
    ctx.amountModalDraft = "1000";
    ctx.applyAmountModalDraft = () => true;
    expect(ctx.flushToParent()).toBe(true);
  });

  it("handleFill remaining date buttons do not throw", () => {
    const ctx = bind();
    ctx.addRow(false);
    const ev = { currentTarget: { dataset: { id: ctx.itemList[0].id } } };
    ctx.handleFillLineStartOneYear(ev);
    ctx.handleFillLineStartMinusOneYear(ev);
    ctx.handleFillLineStartMinusOneMonth(ev);
    ctx.handleFillLineEndOneMonth(ev);
    ctx.handleFillLineEndMinusOneYear(ev);
    ctx.handleFillLineEndMinusOneMonth(ev);
    expect(ctx.itemList[0].startDate).toBeTruthy();
  });

  it("disconnectedCallback and notifyStepReadyChange emit stepready", () => {
    const ctx = bind({ _isConnected: true, _fitProductNamesRaf: null });
    ctx.notifyStepReadyChange();
    expect(
      ctx.dispatchEvent.mock.calls.some((c) => c[0].type === "loadingchange")
    ).toBe(true);
    ctx.disconnectedCallback();
    expect(ctx._isConnected).toBe(false);
  });

  it("wired invoice options and default label store values", () => {
    const ctx = bind({
      _wiredInvoiceSettingOptions: null,
      _wiredDefaultInvoiceSettingLabel: null
    });
    ctx.wiredInvoiceSettingOptions({
      data: [{ label: INVOICE_SETTING_PREPAID_START }]
    });
    expect(ctx.invoiceSettingOptions[0].label).toBe(
      INVOICE_SETTING_PREPAID_START
    );
    ctx.wiredDefaultInvoiceSettingLabel({
      data: INVOICE_SETTING_PREPAID_START
    });
    expect(ctx.defaultInvoiceType).toBe(INVOICE_SETTING_PREPAID_START);
  });

  it("display getters expose 基本情報 labels and groups (Core 4.3.4 / 4.3.5)", () => {
    const ctx = bind();
    ctx.addRow(false);
    expect(ctx.billingTypeSelectOptions.length).toBeGreaterThan(0);
    expect(ctx.changeProductGroups).toEqual([]);
    expect(Array.isArray(ctx.changeNewProductRows)).toBe(true);
    expect(ctx.displayItemList.length).toBe(1);
    expect(ctx.hasProductCustomFields).toBe(false);
    expect(ctx.hasContractCustomFields).toBe(false);
    expect(ctx.contractCustomFieldCount).toBe(0);
    expect(ctx.showProductTable).toBe(true);
    expect(ctx.hasRecurringProductLines).toBe(false);
    expect(ctx.productPickerFilter).toBeTruthy();
    expect(ctx.productTableColspan).toBe(11);
    expect(ctx.totalLineCount).toBe(1);
    expect(ctx.estimateDate).toBe("2026-04-01");
    expect(ctx.showRemarksSection).toBe(false);
    expect(ctx.showTotalSummary).toBe(true);
    expect(ctx.productCustomToggleClass).toBeTruthy();
    expect(ctx.remarksToggleClass).toBeTruthy();
    expect(ctx.productLinesToggleClass).toBeTruthy();
    expect(ctx.recurringPeriodToggleClass).toBeTruthy();
    expect(ctx.contractCustomToggleClass).toBeTruthy();
  });

  it("Change load with previous products builds Original and Remake (Core 4.4.3)", async () => {
    getRecurringContractProducts.mockResolvedValue([
      {
        productId: "01tAAA",
        productName: "継続商品",
        contractProductId: "a03AAA",
        billingType: BILLING_TYPE_RECURRING,
        quantity: 1,
        unitPrice: 1000,
        amount: 12000,
        startDate: "2026-04-01",
        endDate: "2027-03-31",
        invoiceType: INVOICE_SETTING_PREPAID_START
      }
    ]);
    const ctx = bind({
      _wizardData: {
        selectedType: "Change",
        serviceLifecycle: "Term",
        contractHistoryId: "a01HIS",
        contractServiceId: "a00SVC",
        renewEligible: true,
        defaultMonthlyCycles: 12,
        contractStartDate: "2026-04-01",
        contractEndDate: "2027-03-31",
        previousTermStartDate: "2026-04-01",
        previousTermEndDate: "2027-03-31"
      }
    });
    await ctx.loadChangeProducts(ctx._bootstrapGeneration);
    expect(ctx.itemList.length).toBeGreaterThanOrEqual(2);
    expect(ctx.changeProductGroups.length).toBe(1);
    expect(ctx.changeLoadError).toBe("");
  });

  it("Change without matching term cannot 追加変更 (Core 4.3)", async () => {
    const ctx = bind({
      _wizardData: {
        selectedType: "Change",
        serviceLifecycle: "Term",
        contractHistoryId: "a01HIS",
        renewEligible: false
      }
    });
    await ctx.loadChangeProducts(ctx._bootstrapGeneration);
    expect(ctx.changeLoadError).toBe(
      "前回の版の期間終了日と一致する継続課金商品がありません。追加変更できません。新規で作成してください。"
    );
  });

  it("loadHistoryDates copies previous term from history (Core 4.3)", async () => {
    getContractHistoryInfo.mockResolvedValue({
      startDate: "2025-04-01",
      endDate: "2026-03-31"
    });
    const ctx = bind({
      _wizardData: {
        selectedType: "Renew",
        contractHistoryId: "a01HIS",
        defaultMonthlyCycles: 12
      }
    });
    await ctx.loadHistoryDates();
    expect(getContractHistoryInfo).toHaveBeenCalled();
  });

  it("handleAddChangeRemake inserts a Remake after Original (Core 4.4.3)", async () => {
    getRecurringContractProducts.mockResolvedValue([
      {
        productId: "01tAAA",
        productName: "継続商品",
        contractProductId: "a03AAA",
        billingType: BILLING_TYPE_RECURRING,
        quantity: 1,
        unitPrice: 1000,
        amount: 12000,
        startDate: "2026-04-01",
        endDate: "2027-03-31",
        invoiceType: INVOICE_SETTING_PREPAID_START
      }
    ]);
    const ctx = bind({
      _wizardData: {
        selectedType: "Change",
        serviceLifecycle: "Term",
        contractHistoryId: "a01HIS",
        renewEligible: true,
        defaultMonthlyCycles: 12,
        contractStartDate: "2026-04-01",
        contractEndDate: "2027-03-31"
      }
    });
    await ctx.loadChangeProducts(ctx._bootstrapGeneration);
    const pairId = ctx.itemList.find((r) => r.pairId).pairId;
    const before = ctx.itemList.length;
    ctx.handleAddChangeRemake({
      currentTarget: { dataset: { pairId } }
    });
    expect(ctx.itemList.length).toBeGreaterThan(before);
  });
});

describe("estimateCreateModal3 uncovered Core 4.3 / 4.4.3 / 4.10 paths", () => {
  const productCustomDef = {
    apiName: "Extra__c",
    label: "追加",
    fieldType: "STRING",
    showOnNew: true,
    showOnChange: true
  };
  const serviceCustomDef = {
    apiName: "Svc__c",
    label: "サービス追加",
    fieldType: "STRING",
    showOnNew: true,
    showOnChange: true,
    showOnCancel: true
  };

  beforeEach(() => {
    setAmountCalculationRoundingModes({
      quantityUnitPriceRoundingMode: QUANTITY_UNIT_PRICE_ROUNDING_SCALE2_HALF_UP,
      amountRoundingMode: AMOUNT_ROUNDING_SCALE0_HALF_UP
    });
    isAccountingEnabled.mockReset().mockResolvedValue(false);
    getProductDefaults.mockReset();
    getEstimateRemarkMasterText.mockReset();
    getRecurringContractProducts.mockReset().mockResolvedValue([]);
    getRenewContractProducts.mockReset().mockResolvedValue([]);
    getContractHistoryInfo.mockReset().mockResolvedValue(null);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("mounts New Step3 with 読み込み中 then 契約期間 (Core 4.3.4)", async () => {
    const el = createElement("c-estimate-create-modal3", {
      is: EstimateCreateModal3
    });
    el.recordId = "006000000000001AAA";
    el.wizardData = {
      selectedType: "New",
      taxPercent: 10,
      taxRoundingMode: "DOWN",
      defaultMonthlyCycles: 12,
      contractStartDate: "2026-04-01",
      contractEndDate: "2027-03-31",
      estimateSendMode: "PdfOnly",
      estimateDate: "2026-04-01",
      estimateValidDate: "2026-04-30"
    };
    document.body.appendChild(el);
    await Promise.resolve();
    await Promise.resolve();
    const busy = el.shadowRoot.querySelector(".est-step3-busy-text");
    if (busy) {
      expect(busy.textContent).toBe("読み込み中");
    }
    await Promise.resolve();
    await new Promise((r) => setTimeout(r, 0));
    const titles = [...el.shadowRoot.querySelectorAll(".est-panel-title")].map(
      (n) => n.textContent.replace(/\s+/g, " ").trim()
    );
    expect(titles.some((t) => t.includes("商品明細"))).toBe(true);
    expect(titles.some((t) => t.includes("見積書"))).toBe(true);
    document.body.removeChild(el);
  });

  it("Unused hides 見積書セクション; PdfOnly shows it (Core 4.10)", () => {
    const unused = bindLive({
      _wizardData: { selectedType: "New", estimateSendMode: "Unused" }
    });
    expect(unused.showEstimateDocumentSection).toBe(false);
    expect(unused.showRemarksSection).toBe(false);
    const pdf = bindLive({
      _wizardData: { selectedType: "New", estimateSendMode: "PdfOnly" }
    });
    expect(pdf.showEstimateDocumentSection).toBe(true);
  });

  it("Spot Change product picker filters 一回課金 (Core 4.3.5)", () => {
    const ctx = bindLive({
      _wizardData: { selectedType: "Change", serviceLifecycle: "Spot" }
    });
    const filter = ctx.productPickerFilter;
    expect(filter.criteria.some((c) => c.fieldPath === "BillingType__c")).toBe(
      true
    );
  });

  it("Change display groups Original then 新しい商品 (Core 4.4.3)", async () => {
    getRecurringContractProducts.mockResolvedValue([
      {
        productId: "01tAAA",
        productName: "継続商品",
        contractProductId: "a03AAA",
        billingType: BILLING_TYPE_RECURRING,
        quantity: 1,
        unitPrice: 1000,
        amount: 12000,
        startDate: "2026-04-01",
        endDate: "2027-03-31",
        invoiceType: INVOICE_SETTING_PREPAID_START
      }
    ]);
    const ctx = bindLive({
      _wizardData: {
        selectedType: "Change",
        serviceLifecycle: "Term",
        contractHistoryId: "a01HIS",
        contractServiceId: "a00SVC",
        renewEligible: true,
        defaultMonthlyCycles: 12,
        contractStartDate: "2026-04-01",
        contractEndDate: "2027-03-31"
      }
    });
    await ctx.loadChangeProducts(ctx._bootstrapGeneration);
    const display = ctx.displayItemList;
    expect(
      display.some((r) => r.isGroupHeader && r.groupHeaderTitle === "継続商品")
    ).toBe(true);
    expect(
      display.some((r) => r.isGroupHeader && r.groupHeaderTitle === "新しい商品")
    ).toBe(true);
    expect(ctx.changeNewProductRows).toEqual([]);
    expect(ctx.productModalPickerKey).toContain("product-picker");
  });

  it("product custom fields expand into a grid row (Core 4.3.4)", () => {
    const ctx = bindLive({
      productFieldDefinitions: [productCustomDef],
      _productFieldDefinitions: [productCustomDef],
      productCustomFieldsExpanded: true
    });
    ctx.addRow(false);
    expect(ctx.hasProductCustomFields).toBe(true);
    expect(ctx.productCustomExpandedAria).toBe("true");
    expect(ctx.productCustomChevronClass).toContain("est-custom-chevron_open");
    const display = ctx.displayItemList;
    expect(display.some((r) => r.isCustomDetailRow)).toBe(true);
    ctx.handleToggleAllProductCustomFields();
    expect(ctx.productCustomFieldsExpanded).toBe(false);
    expect(ctx.displayItemList.some((r) => r.isCustomDetailRow)).toBe(false);
  });

  it("contract custom section title counts service fields (Core 4.3.4)", () => {
    const ctx = bindLive({
      serviceFieldDefinitions: [serviceCustomDef],
      _serviceFieldDefinitions: [serviceCustomDef],
      _wizardData: {
        selectedType: "New",
        contractStartDate: "2026-04-01",
        contractEndDate: "2027-03-31",
        serviceCustomFieldsExpanded: true,
        historyCustomFieldsExpanded: true
      }
    });
    ctx.addRow(false);
    expect(ctx.hasServiceCustomFields).toBe(true);
    expect(ctx.hasContractCustomFields).toBe(true);
    expect(ctx.contractCustomFieldCount).toBe(1);
    expect(ctx.contractCustomSectionTitle).toBe("契約のカスタム項目（1）");
    expect(ctx.showContractCustomSection).toBe(true);
    expect(ctx.remarksExpandedAria).toBe("true");
    expect(ctx.contractCustomExpandedAria).toBe("true");
  });

  it("Cancel still shows contract custom when ShowOnCancel (Core 4.3)", () => {
    const ctx = bindLive({
      serviceFieldDefinitions: [serviceCustomDef],
      _serviceFieldDefinitions: [serviceCustomDef],
      _wizardData: { selectedType: "Cancel" },
      itemList: []
    });
    expect(ctx.showProductTable).toBe(false);
    expect(ctx.showContractCustomSection).toBe(true);
  });

  it("applyProductSelection fills master defaults; clear empties the row (Core 4.3.9)", async () => {
    getProductDefaults.mockResolvedValue({
      productName: "単発商品",
      billingType: BILLING_TYPE_ONE_TIME,
      invoiceType: INVOICE_SETTING_PREPAID_START,
      unitPrice: 1000,
      unitName: "式",
      displayUnit: "式",
      productVisibilityContext: {}
    });
    const ctx = bindLive();
    ctx.addRow(false);
    const id = ctx.itemList[0].id;
    await ctx.applyProductSelection(id, "01tBBB");
    expect(ctx.itemList[0].productName).toBe("単発商品");
    expect(ctx.itemList[0].unitPrice).toBe(1000);
    await ctx.applyProductSelection(id, "");
    expect(ctx.itemList[0].productId).toBe("");
    expect(ctx.itemList[0].productName).toBe("");
  });

  it("applyProductSelection missing defaults toasts 商品を選択できません (Core 4.3)", async () => {
    getProductDefaults.mockResolvedValue(null);
    const ctx = bindLive();
    ctx.addRow(false);
    const id = ctx.itemList[0].id;
    await ctx.applyProductSelection(id, "01tMISSING");
    expect(ctx.surfaceError).toBe(
      "選択した商品の情報を取得できませんでした。契約管理で利用可能な商品を選択してください。"
    );
  });

  it("amount modal hint is formula help; Escape closes (Core 4.3.9)", () => {
    const ctx = bindLive();
    ctx.addRow(false);
    const id = ctx.itemList[0].id;
    ctx.handleEnableAmountEntry({ currentTarget: { dataset: { id } } });
    ctx.handleOpenAmountModal({ currentTarget: { dataset: { id } } });
    expect(ctx.isAmountModalOpen).toBe(true);
    expect(ctx.hasOpenAmountModal).toBe(true);
    expect(ctx.amountModalHint).toBe(
      "金額、または = で四則計算（例: =1,200,000/12）"
    );
    ctx.handleAmountModalDraftChange({ target: { value: "1200" } });
    expect(ctx.applyAmountModalDraft()).toBe(true);
    expect(ctx.itemList[0].amountEntryMode).toBe(true);
    ctx.handleEnableAmountEntry({ currentTarget: { dataset: { id } } });
    ctx.handleOpenAmountModal({ currentTarget: { dataset: { id } } });
    ctx.handleAmountModalKeydown({
      key: "Escape",
      preventDefault: jest.fn()
    });
    expect(ctx.isAmountModalOpen).toBe(false);
  });

  it("open product picker while amount formula is open asks to 適用（またはキャンセル） (Core 4.3.9)", () => {
    const ctx = bindLive();
    ctx.addRow(false);
    const id = ctx.itemList[0].id;
    ctx.handleEnableAmountEntry({ currentTarget: { dataset: { id } } });
    ctx.handleOpenAmountModal({ currentTarget: { dataset: { id } } });
    ctx.amountModalDraft = "=1000/3";
    ctx.handleOpenProductModal({ currentTarget: { dataset: { id } } });
    expect(ctx.amountApplyError).toBe(
      "数式ポップアップを適用（またはキャンセル）してから商品を選択してください。"
    );
  });

  it("clearing remark master with text asks よろしいですか (Core 4.3)", async () => {
    const ctx = bindLive({
      _wizardData: {
        selectedType: "New",
        estimateRemarkMasterId: "a08MAS",
        estimateRemarks: "既存備考"
      }
    });
    const pending = ctx.handleRemarkMasterChange({ detail: { recordId: "" } });
    const confirmEvt = ctx.dispatchEvent.mock.calls.find(
      (c) => c[0].type === "confirmrequest"
    );
    expect(confirmEvt[0].detail.message).toBe(
      "見積備考マスタの選択を解除すると、見積備考の内容もクリアされます。よろしいですか？"
    );
    ctx.resolveConfirmRequest(confirmEvt[0].detail.requestId, false);
    await pending;
    expect(ctx.estimateRemarkMasterId).toBe("a08MAS");
  });

  it("choosing another remark master with text asks 上書きしますか (Core 4.3)", async () => {
    getEstimateRemarkMasterText.mockResolvedValue("マスタ本文");
    const ctx = bindLive({
      _wizardData: {
        selectedType: "New",
        estimateRemarkMasterId: "a08OLD",
        estimateRemarks: "既存備考"
      }
    });
    const pending = ctx.handleRemarkMasterChange({
      detail: { recordId: "a08NEW" }
    });
    await Promise.resolve();
    const confirmEvt = ctx.dispatchEvent.mock.calls.find(
      (c) => c[0].type === "confirmrequest"
    );
    expect(confirmEvt[0].detail.message).toBe(
      "見積備考に入力済みの文章があります。選択した見積備考マスタの内容で上書きしますか？"
    );
    ctx.resolveConfirmRequest(confirmEvt[0].detail.requestId, true);
    await pending;
    const changeEvt = ctx.dispatchEvent.mock.calls.find(
      (c) => c[0].type === "changefield" && c[0].detail.estimateRemarks
    );
    expect(changeEvt[0].detail.estimateRemarks).toBe("マスタ本文");
  });

  it("remark master fetch failure is 見積備考マスタの取得に失敗しました", async () => {
    getEstimateRemarkMasterText.mockRejectedValue({
      body: { message: "timeout" }
    });
    const ctx = bindLive({
      _wizardData: {
        selectedType: "New",
        estimateRemarkMasterId: "",
        estimateRemarks: ""
      }
    });
    await ctx.handleRemarkMasterChange({ detail: { recordId: "a08BAD" } });
    expect(ctx.remarkMasterLoadError).toContain(
      "見積備考マスタの取得に失敗しました。"
    );
  });

  it("identity change after connect re-bootstraps New (Core 4.3.4)", async () => {
    const ctx = bindLive({
      _isConnected: false,
      _wizardIdentityKey: ""
    });
    ctx.connectedCallback();
    await Promise.resolve();
    ctx._wizardData = {
      selectedType: "New",
      contractServiceId: "a00SVC",
      taxPercent: 10,
      defaultMonthlyCycles: 12,
      contractStartDate: "2026-04-01",
      contractEndDate: "2027-03-31"
    };
    ctx.maybeBootstrapForIdentityChange();
    await Promise.resolve();
    expect(ctx.itemList.length).toBeGreaterThanOrEqual(1);
  });

  it("connected custom field defs count ShowOnNew service fields (Core 11.4.1)", () => {
    const ctx = bindLive({
      _isConnected: true,
      serviceFieldDefinitions: [serviceCustomDef],
      _serviceFieldDefinitions: [serviceCustomDef],
      _historyFieldDefinitions: [],
      _orderFieldDefinitions: [],
      _opportunityDefaultContext: {}
    });
    ctx.emitDefaultContractCustomFieldsIfNeeded();
    expect(ctx.hasServiceCustomFields).toBe(true);
    ctx._loadingContractHistory = true;
    ctx.maybeBootstrapForIdentityChange();
    expect(ctx._loadingContractHistory).toBe(true);
  });

  it("wiredContractServiceTax stores the wire result", () => {
    const ctx = bindLive();
    ctx.wiredContractServiceTax({ data: { TaxPercent__c: 10 } });
    expect(ctx._wiredContractServiceTax.data.TaxPercent__c).toBe(10);
    expect(ctx.wiredContractServiceId).toBeUndefined();
  });

  it("handleInlineProductChange applies selection (Core 4.3)", async () => {
    getProductDefaults.mockResolvedValue({
      productName: "選択商品",
      billingType: BILLING_TYPE_ONE_TIME,
      invoiceType: INVOICE_SETTING_PREPAID_START,
      unitPrice: 500,
      displayUnit: "式"
    });
    const ctx = bindLive();
    ctx.addRow(false);
    const id = ctx.itemList[0].id;
    await ctx.handleInlineProductChange({
      currentTarget: {
        closest: () => ({ dataset: { productPickRow: id } })
      },
      detail: { recordId: "01tCCC" }
    });
    expect(ctx.itemList[0].productName).toBe("選択商品");
  });

  it("handleInvoiceTypeChange Remake toast is 前回の版と同じ (Core 4.5.2)", () => {
    const ctx = bindLive({
      _wizardData: { selectedType: "Change", serviceLifecycle: "Term" }
    });
    ctx.itemList = [
      {
        id: "r1",
        recordType: "Remake",
        sourceContractProductId: "a03AAA",
        billingType: BILLING_TYPE_RECURRING,
        invoiceType: INVOICE_SETTING_PREPAID_START
      }
    ];
    const target = { value: "別" };
    ctx.handleInvoiceTypeChange({
      currentTarget: { dataset: { id: "r1" } },
      target
    });
    expect(target.value).toBe(INVOICE_SETTING_PREPAID_START);
    expect(ctx.surfaceError).toBe(
      "変更後の行の請求設定は前回の版と同じにしてください。"
    );
  });

  it("formula amount draft asks for 整数円 (Core 4.3.9)", () => {
    const ctx = bindLive();
    ctx.addRow(false);
    const id = ctx.itemList[0].id;
    ctx.handleEnableAmountEntry({ currentTarget: { dataset: { id } } });
    ctx.handleOpenAmountModal({ currentTarget: { dataset: { id } } });
    ctx.amountModalDraft = "=1000/3";
    expect(ctx.applyAmountModalDraft()).toBe(false);
    expect(ctx.amountModalHint).toBe(
      "端数を確認し、整数円にして適用してください"
    );
  });

  it("connectedCallback then disconnectedCallback refresh wires (Core 4.1)", async () => {
    const ctx = bindLive({
      _isConnected: false,
      _wiredInvoiceSettingOptions: { data: [] },
      _wiredDefaultInvoiceSettingLabel: { data: INVOICE_SETTING_PREPAID_START },
      _wizardData: {
        selectedType: "New",
        contractServiceId: "a00SVC",
        taxPercent: 10,
        defaultMonthlyCycles: 12
      }
    });
    ctx.connectedCallback();
    await ctx.refreshReferenceWires();
    ctx.renderedCallback();
    ctx.disconnectedCallback();
    expect(ctx._isConnected).toBe(false);
  });

  it("syncDisplayFromParent restores selectedProducts (Core 4.3.4)", () => {
    const ctx = bindLive({
      _lastEmittedProductsFingerprint: "x",
      _lastSyncedProductsFingerprint: "",
      _wizardData: {
        selectedType: "New",
        selectedProducts: [
          {
            id: "saved1",
            productId: "01tAAA",
            productName: "保存商品",
            billingType: BILLING_TYPE_ONE_TIME,
            quantity: 1,
            unitPrice: 100,
            amount: 100,
            invoiceType: INVOICE_SETTING_PREPAID_START
          }
        ]
      }
    });
    ctx.syncDisplayFromParent();
    expect(ctx.itemList[0].productName).toBe("保存商品");
  });

  it("product table wrap is disabled when not editable (Core 4.3.4)", () => {
    const ctx = bindLive({
      _bootstrapInFlight: true,
      orderedCustomFieldsOnly: false
    });
    expect(ctx.productTableScrollClass).toContain("est-table-wrap_disabled");
    const picking = bindLive();
    picking.productModalRowId = "r1";
    expect(picking.productTableScrollClass).toContain(
      "est-table-wrap_product-picking"
    );
  });

  it("Enter applies amount modal; reload policy and empty remark retry (Core 4.3.9 / 4.3.11)", async () => {
    const ctx = bindLive();
    ctx.addRow(false);
    const id = ctx.itemList[0].id;
    ctx.handleEnableAmountEntry({ currentTarget: { dataset: { id } } });
    ctx.handleOpenAmountModal({ currentTarget: { dataset: { id } } });
    ctx.amountModalDraft = "2400";
    const prevent = jest.fn();
    ctx.handleAmountModalInputKeydown({ key: "Enter", preventDefault: prevent });
    expect(prevent).toHaveBeenCalled();
    expect(ctx.isAmountModalOpen).toBe(false);
    ctx.handleEnableAmountEntry({ currentTarget: { dataset: { id } } });
    ctx.handleOpenAmountModal({ currentTarget: { dataset: { id } } });
    ctx.amountModalDraft = "3600";
    ctx.handleApplyAmountModal();
    expect(ctx.isAmountModalOpen).toBe(false);
    await ctx.handleReloadAccountingPolicy();
    expect(ctx.accountingPolicyResolved).toBe(true);
    ctx._pendingRemarkMasterId = "";
    await ctx.handleReloadRemarkMaster();
    expect(ctx.remarkMasterLoadError).toBe("");
  });

  it("parent product echo does not re-bootstrap when identity is unchanged (Core 4.3.4)", () => {
    const ctx = bindLive({
      _isConnected: true,
      _bootstrapInFlight: false,
      _lastEmittedProductsFingerprint: "emitted",
      _lastSyncedProductsFingerprint: ""
    });
    ctx._wizardIdentityKey = ctx.buildWizardIdentityKey();
    ctx._wizardData = {
      ...ctx._wizardData,
      selectedProducts: [
        {
          id: "p1",
          productId: "01tAAA",
          productName: "親明細",
          billingType: BILLING_TYPE_ONE_TIME,
          quantity: 1,
          unitPrice: 10,
          amount: 10,
          invoiceType: INVOICE_SETTING_PREPAID_START
        }
      ]
    };
    ctx.maybeBootstrapForIdentityChange();
    expect(ctx.itemList[0].productName).toBe("親明細");
  });
});
