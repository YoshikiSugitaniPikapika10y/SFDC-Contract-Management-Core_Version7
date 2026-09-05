import { NavigationMixin } from "lightning/navigation";
import EstimateCreateModal2 from "c/estimateCreateModal2";

const Navigate = Symbol.for("NavigationMixin.Navigate");

jest.mock(
  "lightning/navigation",
  () => ({
    NavigationMixin: Object.assign(
      (Base) =>
        class extends Base {
          [Navigate]() {}
        },
      { Navigate }
    )
  }),
  { virtual: true }
);

describe("estimateCreateModal2 billing account formal edit (Core 4.3.3)", () => {
  const proto = EstimateCreateModal2.prototype;

  it("navigates to BillingAccount__c edit when 19 can update", () => {
    const navigate = jest.fn();
    const opened = proto.handleOpenBillingAccountFormalEdit.call({
      billingAccountId: "a00BA0000000001",
      canUpdateBillingAccount: true,
      [Navigate]: navigate
    });
    expect(opened).toBe(true);
    expect(navigate).toHaveBeenCalledWith({
      type: "standard__recordPage",
      attributes: {
        recordId: "a00BA0000000001",
        objectApiName: "BillingAccount__c",
        actionName: "edit"
      }
    });
  });

  it("hides the Edit navigation without 19", () => {
    const show = Object.getOwnPropertyDescriptor(
      proto,
      "showBillingAccountFormalEdit"
    ).get;
    expect(
      show.call({
        billingAccountId: "a00BA0000000001",
        canUpdateBillingAccount: false
      })
    ).toBe(false);
    const navigate = jest.fn();
    expect(
      proto.handleOpenBillingAccountFormalEdit.call({
        billingAccountId: "a00BA0000000001",
        canUpdateBillingAccount: false,
        [Navigate]: navigate
      })
    ).toBe(false);
    expect(navigate).not.toHaveBeenCalled();
  });
});
