import OrderCreateStepBilling from "c/orderCreateStepBilling";
import { refreshApex } from "@salesforce/apex";
import { getRecordNotifyChange } from "lightning/uiRecordApi";
import { buildCustomFieldInputs } from "c/estimateWizardCustomFields";
import { invoiceDateMethodHelp, METHOD_SAME_DAY, METHOD_MONTH_OFFSET } from "c/billingAccountForm";

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
  "c/estimateWizardCustomFields",
  () => ({ buildCustomFieldInputs: jest.fn(() => []) }),
  { virtual: true }
);
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
    _objectInfo: { updateable: true },
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
    buildCustomFieldInputs.mockReset().mockReturnValue([]);
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

  it("refreshReferenceWires notifies LDS (Core 5.2)", async () => {
    const ctx = bind();
    await ctx.refreshReferenceWires();
    expect(refreshApex).toHaveBeenCalled();
    expect(getRecordNotifyChange).toHaveBeenCalled();
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

  it("object info missing still allows formal edit (共通基盤 10.4)", () => {
    const ctx = bind({ _objectInfo: undefined });
    expect(ctx.canUpdateBillingAccount).toBe(true);
    expect(ctx.showFormalEditButton).toBe(true);
    ctx.wiredBillingAccountObjectInfo({ data: { updateable: false } });
    expect(ctx.canUpdateBillingAccount).toBe(false);
  });

  it("invoice/payment help and field groups (Core 7.2 / 7.5)", () => {
    buildCustomFieldInputs.mockReturnValue([
      {
        apiName: "BillingAddressee__c",
        displayValue: "",
        required: true
      },
      {
        apiName: "InvoiceDateMethod__c",
        displayValue: METHOD_SAME_DAY,
        required: true
      },
      {
        apiName: "PaymentTermMethod__c",
        displayValue: METHOD_MONTH_OFFSET,
        required: true
      }
    ]);
    const ctx = bind({
      _billingCustomFields: {
        InvoiceDateMethod__c: METHOD_SAME_DAY,
        PaymentTermMethod__c: METHOD_MONTH_OFFSET
      }
    });
    expect(ctx.invoiceDateHelp).toBe(invoiceDateMethodHelp(METHOD_SAME_DAY));
    expect(ctx.deliveryFieldInputs.length).toBe(1);
    expect(ctx.invoiceDateFieldInputs.length).toBe(1);
    expect(ctx.paymentTermFieldInputs.length).toBe(1);
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
