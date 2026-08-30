import EstimateCreateModal2 from "c/estimateCreateModal2";

jest.mock(
  "@salesforce/apex/EstimateCreateController.getBillingAccountsByAccount",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.getActiveContractServicesByAccount",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

describe("estimateCreateModal2 service picker (Core 第0.1節)", () => {
  it("shows 版 not V prefix for Version", () => {
    const option = EstimateCreateModal2.prototype.buildServicePickerOption.call(
      {},
      { id: "svc1", name: "Service", version: 3 },
      ""
    );
    expect(option.versionLabel).toBe("版3");
    expect(option.versionLabel).not.toMatch(/^V/);
  });
});

describe("estimateCreateModal2 other-account billing (Core 第3.2節・第1.1.10節)", () => {
  const proto = EstimateCreateModal2.prototype;
  const canSearch = Object.getOwnPropertyDescriptor(
    proto,
    "canSearchOtherAccountBilling"
  ).get;
  const showOther = Object.getOwnPropertyDescriptor(
    proto,
    "showOtherBillingPicker"
  ).get;

  it("does not offer other-account billing search without opportunity account", () => {
    expect(
      canSearch.call({
        opportunityAccountId: "",
        orderedCustomFieldsOnly: false
      })
    ).toBe(false);
    expect(
      showOther.call({
        canSearchOtherAccountBilling: false,
        allowOtherAccountBilling: true
      })
    ).toBe(false);
  });
});
