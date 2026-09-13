import {
  RETURN_TO_ORDER,
  buildBillingAccountFormalEditPageRef,
  consumeReturnCaller,
  rememberReturnCaller,
  resolveReturnCaller
} from "c/billingAccountReturnNavigation";

describe("billingAccountReturnNavigation (Core 3.3.3)", () => {
  beforeEach(() => {
    sessionStorage.clear();
  });

  it("remembers return caller when building formal edit page ref", () => {
    const pageRef = buildBillingAccountFormalEditPageRef(
      "a00BA",
      RETURN_TO_ORDER,
      "a0HORDER"
    );
    expect(pageRef.state).toEqual({
      c__returnTo: "order",
      c__returnRecordId: "a0HORDER"
    });
    expect(consumeReturnCaller()).toEqual({
      returnTo: "order",
      returnRecordId: "a0HORDER"
    });
    expect(consumeReturnCaller()).toEqual({
      returnTo: "",
      returnRecordId: ""
    });
  });

  it("resolveReturnCaller falls back to session when page state is empty", () => {
    rememberReturnCaller("estimateCreate", "006OPP", "a00BA");
    expect(
      resolveReturnCaller({
        returnTo: "",
        returnRecordId: "",
        pageRef: { attributes: { actionName: "edit" } },
        billingAccountId: "a00BA"
      })
    ).toEqual({
      returnTo: "estimateCreate",
      returnRecordId: "006OPP"
    });
  });

  it("resolveReturnCaller discards a stash for another billing account", () => {
    rememberReturnCaller("estimateCreate", "006OPP", "a00OLD");
    expect(
      resolveReturnCaller({
        pageRef: {
          attributes: { actionName: "edit", recordId: "a00DIRECT" }
        },
        billingAccountId: "a00DIRECT"
      })
    ).toEqual({
      returnTo: "",
      returnRecordId: ""
    });
    expect(consumeReturnCaller()).toEqual({
      returnTo: "",
      returnRecordId: ""
    });
  });

  it("resolveReturnCaller prefers @api and clears the stash", () => {
    rememberReturnCaller("order", "a0HOLD");
    expect(
      resolveReturnCaller({
        returnTo: "estimateEdit",
        returnRecordId: "a01EDIT",
        pageRef: null
      })
    ).toEqual({
      returnTo: "estimateEdit",
      returnRecordId: "a01EDIT"
    });
    expect(consumeReturnCaller()).toEqual({
      returnTo: "",
      returnRecordId: ""
    });
  });
});
