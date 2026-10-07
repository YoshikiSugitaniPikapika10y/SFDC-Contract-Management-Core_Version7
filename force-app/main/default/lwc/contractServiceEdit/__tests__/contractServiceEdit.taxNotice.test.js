import ContractServiceEdit from "c/contractServiceEdit";

jest.mock(
  "@salesforce/apex/ContractServiceEditController.getContext",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractServiceEditController.save",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractServiceEditController.issueContractServiceOperationKey",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractWizardFieldService.getContractServiceFieldDefinitions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_08_Can_EditService",
  () => ({ default: true }),
  { virtual: true }
);

const proto = ContractServiceEdit.prototype;

function createContext(overrides) {
  const ctx = {
    taxPercent: 10,
    originalBillingAccountId: "saved",
    billingAccountId: "saved",
    unorderedSavedTaxPercents: [],
    orderedSavedTaxPercents: [],
    taxChangeAcknowledged: false,
    ...overrides
  };
  ["taxNotice", "showTaxNotice", "billingAccountNotice", "showBillingAccountNotice"].forEach(
    (name) => {
      const desc = Object.getOwnPropertyDescriptor(proto, name);
      Object.defineProperty(ctx, name, { get: desc.get, configurable: true });
    }
  );
  ctx.differentSavedTaxCounts = proto.differentSavedTaxCounts;
  return ctx;
}

describe("contractServiceEdit tax and billing notices (Core 3.4.1)", () => {
  it("shows the tax band only when a saved rate differs, and the billing band only when reselected", () => {
    const same = createContext({
      unorderedSavedTaxPercents: [10],
      orderedSavedTaxPercents: [10]
    });
    expect(same.taxNotice).toBe("");

    const differed = createContext({
      taxPercent: 8,
      unorderedSavedTaxPercents: [10, null],
      orderedSavedTaxPercents: [8]
    });
    expect(differed.taxNotice).toBe(
      "次に見積を保存するときから、この税率になります。未確定を含め、既存の請求書や受注済みの見積には反映できません。未受注1件"
    );

    const both = createContext({
      taxPercent: 8,
      unorderedSavedTaxPercents: [10],
      orderedSavedTaxPercents: [10]
    });
    expect(both.taxNotice).toContain("未受注1件、受注済み1件");

    const billing = createContext({ billingAccountId: "other" });
    expect(billing.billingAccountNotice).toBe(
      "次の受注と再生成では、この請求先になります。未確定の請求書へ反映するときは、請求ボードから操作してください。"
    );
    expect(createContext().billingAccountNotice).toBe("");
  });
});
