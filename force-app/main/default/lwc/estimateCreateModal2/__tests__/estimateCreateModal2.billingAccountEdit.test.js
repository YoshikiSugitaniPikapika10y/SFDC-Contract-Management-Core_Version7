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
      recordId: "006000000000001AAA",
      editMode: false,
      editHistoryId: "",
      copyFromHistoryId: "",
      resolveBillingAccountReturnCaller:
        proto.resolveBillingAccountReturnCaller,
      [NavigationMixin.Navigate]: navigate
    });
    expect(opened).toBe(true);
    expect(navigate).toHaveBeenCalledWith({
      type: "standard__recordPage",
      attributes: {
        recordId: "a00BA0000000001",
        objectApiName: "BillingAccount__c",
        actionName: "edit"
      },
      state: {
        c__returnTo: "estimateCreate",
        c__returnRecordId: "006000000000001AAA"
      }
    });
  });

  it("passes estimateEdit return caller when editing a history", () => {
    const navigate = jest.fn();
    proto.handleOpenBillingAccountFormalEdit.call({
      billingAccountId: "a00BA0000000001",
      canUpdateBillingAccount: true,
      recordId: "006000000000001AAA",
      editMode: true,
      editHistoryId: "a01EDIT000000001",
      copyFromHistoryId: "",
      resolveBillingAccountReturnCaller:
        proto.resolveBillingAccountReturnCaller,
      [NavigationMixin.Navigate]: navigate
    });
    expect(navigate.mock.calls[0][0].state).toEqual({
      c__returnTo: "estimateEdit",
      c__returnRecordId: "a01EDIT000000001"
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
        [NavigationMixin.Navigate]: navigate
      })
    ).toBe(false);
    expect(navigate).not.toHaveBeenCalled();
  });
});
