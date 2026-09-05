import EstimateCreateModal1 from "c/estimateCreateModal1";

jest.mock(
  "lightning/uiRecordApi",
  () => ({
    getRecord: jest.fn(),
    getFieldValue: jest.fn(),
    getRecordNotifyChange: jest.fn()
  }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/Opportunity.Name",
  () => ({ default: { objectApiName: "Opportunity", fieldApiName: "Name" } }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/Opportunity.Account.Name",
  () => ({
    default: { objectApiName: "Opportunity", fieldApiName: "Account.Name" }
  }),
  { virtual: true }
);
jest.mock(
  "@salesforce/schema/Opportunity.ContactId",
  () => ({
    default: { objectApiName: "Opportunity", fieldApiName: "ContactId" }
  }),
  { virtual: true }
);

const typeOptions = Object.getOwnPropertyDescriptor(
  EstimateCreateModal1.prototype,
  "typeOptions"
).get;

function optionsOf(state) {
  return typeOptions.call(state);
}

describe("estimateCreateModal1 (Core 4.3.3 / 0.1)", () => {
  it("shows type buttons as 新規／追加変更／更新／解約", () => {
    expect(
      optionsOf({
        selectedType: "",
        readOnly: false
      }).map((row) => row.label)
    ).toEqual(["新規", "追加変更", "更新", "解約"]);
  });

  it("does not let Estimate edit change the type", () => {
    expect(
      optionsOf({
        selectedType: "New",
        readOnly: true
      }).every((row) => row.disabled === true)
    ).toBe(true);
  });
});
