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
    if (desc.get) {
      Object.defineProperty(ctx, name, {
        get: desc.get,
        set: desc.set,
        configurable: true
      });
    } else if (typeof desc.value === "function") {
      ctx[name] = desc.value;
    }
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
    expect(loading.stepBusyBannerMessage).toBe(
      "会計方針を読み込んでいます。完了するまで『次へ』『保存』はできません。"
    );
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
