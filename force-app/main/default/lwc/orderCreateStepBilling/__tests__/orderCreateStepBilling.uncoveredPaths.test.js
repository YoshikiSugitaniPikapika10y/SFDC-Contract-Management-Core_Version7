jest.mock(
  "@salesforce/apex/OrderWizardFieldService.getOrderBillingFieldDefinitions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.getBillingAccountInvoiceSettings",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractPermissionUtil.hasBillingAccountSet",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "lightning/uiRecordApi",
  () => {
    class GetRecordAdapter {}
    return {
      getRecord: GetRecordAdapter,
      getFieldValue: jest.fn(),
      getRecordNotifyChange: jest.fn()
    };
  },
  { virtual: true }
);
jest.mock(
  "lightning/uiObjectInfoApi",
  () => {
    class GetObjectInfoAdapter {}
    return { getObjectInfo: GetObjectInfoAdapter };
  },
  { virtual: true }
);
jest.mock("@salesforce/apex", () => ({ refreshApex: jest.fn() }), {
  virtual: true
});
jest.mock(
  "lightning/navigation",
  () => {
    const Navigate = Symbol.for("NavigationMixin.Navigate");
    return {
      NavigationMixin: Object.assign(
        (Base) =>
          class extends Base {
            [Navigate]() {}
          },
        { Navigate }
      ),
      CurrentPageReference: class CurrentPageReference {}
    };
  },
  { virtual: true }
);
jest.mock(
  "lightning/actions",
  () => ({ CloseActionScreenEvent: class CloseActionScreenEvent {} }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/BillingAccount__c",
  () => ({ default: { objectApiName: "BillingAccount__c" } }),
  { virtual: true }
);

const OrderCreateStepBilling = require("c/orderCreateStepBilling").default;
const { refreshApex } = require("@salesforce/apex");
const { getRecordNotifyChange } = require("lightning/uiRecordApi");
const {
  invoiceDateMethodHelp,
  METHOD_SAME_DAY,
  METHOD_MONTH_OFFSET
} = require("c/billingAccountForm");

const proto = OrderCreateStepBilling.prototype;

function bind(overrides = {}) {
  const ctx = {
    context: {
      billingAccountId: "a00BA",
      billingAccountName: "BA-1",
      billingAccountKey: "KEY-1",
      billingCustomerAccountName: "取引先A"
    },
    busy: false,
    _billingCustomFields: { InvoiceDateMethod__c: METHOD_SAME_DAY },
    _pendingBillingCustomFields: null,
    _wiredFieldDefinitions: { data: [] },
    _wiredBillingAccountInvoiceSettings: { data: {} },
    fieldDefinitions: [],
    _hasBillingAccountSet: true,
    ...overrides
  };
  Object.getOwnPropertyNames(proto).forEach((name) => {
    if (name === "constructor") {
      return;
    }
    const desc = Object.getOwnPropertyDescriptor(proto, name);
    if (!desc || (desc.get && desc.set)) {
      return;
    }
    if (Object.prototype.hasOwnProperty.call(ctx, name)) {
      return;
    }
    if (desc.get && !desc.set) {
      Object.defineProperty(ctx, name, { get: desc.get, configurable: true });
    } else if (typeof desc.value === "function") {
      ctx[name] = desc.value;
    }
  });
  return ctx;
}

describe("orderCreateStepBilling uncovered (Core 5.2 / 7.2 / 7.5)", () => {
  beforeEach(() => {
    refreshApex.mockReset().mockResolvedValue();
    getRecordNotifyChange.mockClear();
  });

  it("empty billing names show — (Core 5.2)", () => {
    const ctx = bind({ context: {} });
    expect(ctx.billingCustomerAccountName).toBe("—");
    expect(ctx.billingAccountName).toBe("—");
    expect(ctx.billingAccountKey).toBe("—");
    expect(ctx.formatDisplayValue(null)).toBe("—");
    expect(ctx.formatDisplayValue("  ")).toBe("—");
    expect(ctx.formatDisplayValue("宛名")).toBe("宛名");
  });

  it("refreshReferenceWires reloads the latest billing values and notifies LDS (Core 5.2)", async () => {
    const ctx = bind({
      _wiredFieldDefinitions: null,
      fieldDefinitions: [
        {
          apiName: "BillingAddressee__c",
          label: "宛名",
          fieldType: "STRING",
          required: true
        }
      ],
      _billingCustomFields: { BillingAddressee__c: "変更前の宛名" }
    });
    refreshApex.mockImplementationOnce(() => {
      ctx.wiredBillingAccountInvoiceSettings({
        data: {
          billingCustomFields: { BillingAddressee__c: "最新の宛名" }
        }
      });
      return Promise.resolve();
    });

    await ctx.refreshReferenceWires();
    expect(ctx.getBillingCustomFields().BillingAddressee__c).toBe("最新の宛名");
    expect(getRecordNotifyChange).toHaveBeenCalledWith([
      { recordId: "a00BA" }
    ]);
  });

  it("getBillingCustomFields fills missing STRING as empty", () => {
    const ctx = bind({
      fieldDefinitions: [
        { apiName: "BillingAddressee__c", fieldType: "STRING" }
      ],
      _billingCustomFields: {}
    });
    expect(ctx.getBillingCustomFields().BillingAddressee__c).toBe("");
  });

  it("validate skips hidden schedule fields (Core 5.2 / 7.2)", () => {
    const ctx = bind({
      fieldDefinitions: [
        {
          apiName: "InvoiceDateDayOffset__c",
          label: "日数",
          fieldType: "DOUBLE",
          required: true
        },
        {
          apiName: "Note__c",
          label: "メモ",
          fieldType: "STRING",
          required: false
        }
      ],
      _billingCustomFields: { InvoiceDateMethod__c: METHOD_SAME_DAY }
    });
    expect(ctx.validateBillingFields()).toBe(null);
  });

  it("BOOLEAN required is never missing", () => {
    const ctx = bind();
    expect(ctx.isMissingBillingFieldValue("BOOLEAN", false)).toBe(false);
    expect(ctx.isMissingBillingFieldValue("STRING", null)).toBe(true);
  });

  it("wiredFieldDefinitions applies fallback (Core 5.2)", () => {
    const ctx = bind({
      fieldDefinitions: [],
      _pendingBillingCustomFields: { BillingAddressee__c: "A" },
      context: { billingSettings: { billingCustomFields: { X__c: "1" } } }
    });
    ctx.wiredFieldDefinitions({
      data: [{ apiName: "BillingAddressee__c", fieldType: "STRING" }]
    });
    expect(ctx.fieldDefinitions).toHaveLength(1);
    ctx.wiredFieldDefinitions({ data: undefined });
  });

  it("permission set 19 gates formal edit; 101 object update does not (共通基盤 10.4)", () => {
    const without19 = bind({ _hasBillingAccountSet: false });
    expect(without19.canUpdateBillingAccount).toBe(false);
    expect(without19.showFormalEditButton).toBe(false);
    const with19 = bind({ _hasBillingAccountSet: true });
    expect(with19.canUpdateBillingAccount).toBe(true);
    expect(with19.showFormalEditButton).toBe(true);
    with19.wiredBillingAccountSet({ data: false });
    expect(with19.canUpdateBillingAccount).toBe(false);
  });

  it("invoice/payment help and field groups (Core 7.2 / 7.5)", () => {
    const ctx = bind({
      fieldDefinitions: [
        {
          apiName: "BillingAddressee__c",
          label: "宛名",
          fieldType: "STRING",
          required: true
        },
        {
          apiName: "InvoiceDateMethod__c",
          label: "請求日の計算方式",
          fieldType: "PICKLIST",
          required: true,
          picklistOptions: [
            { label: "基準日と同日", value: METHOD_SAME_DAY }
          ]
        },
        {
          apiName: "InvoiceDateDayOffset__c",
          label: "請求日の指定日数",
          fieldType: "DOUBLE",
          required: true
        },
        {
          apiName: "PaymentTermMethod__c",
          label: "支払条件の計算方式",
          fieldType: "PICKLIST",
          required: true,
          picklistOptions: [
            { label: "請求月から指定月数後", value: METHOD_MONTH_OFFSET }
          ]
        }
      ],
      _billingCustomFields: {
        BillingAddressee__c: "",
        InvoiceDateMethod__c: METHOD_SAME_DAY,
        PaymentTermMethod__c: METHOD_MONTH_OFFSET
      }
    });
    expect(ctx.invoiceDateHelp).toBe(invoiceDateMethodHelp(METHOD_SAME_DAY));
    expect(ctx.deliveryFieldInputs.map((field) => field.displayValue)).toEqual([
      "—"
    ]);
    expect(
      ctx.invoiceDateFieldInputs.map((field) => field.displayValue)
    ).toEqual(["基準日と同日"]);
    expect(
      ctx.paymentTermFieldInputs.map((field) => field.displayValue)
    ).toEqual(["請求月から指定月数後"]);
    expect(
      ctx.invoiceDateFieldInputs.some(
        (field) => field.apiName === "InvoiceDateDayOffset__c"
      )
    ).toBe(false);
  });

  it("wired invoice settings no-ops without definitions", () => {
    const ctx = bind({ fieldDefinitions: [] });
    ctx.wiredBillingAccountInvoiceSettings({ data: { billingCustomFields: {} } });
    ctx.applyBillingSettingsFallback(null);
  });

  it("handleOpenFormalEdit when not busy", () => {
    const ctx = bind({
      openBillingAccountFormalEdit: jest.fn()
    });
    ctx.handleOpenFormalEdit();
    expect(ctx.openBillingAccountFormalEdit).toHaveBeenCalled();
  });
});
