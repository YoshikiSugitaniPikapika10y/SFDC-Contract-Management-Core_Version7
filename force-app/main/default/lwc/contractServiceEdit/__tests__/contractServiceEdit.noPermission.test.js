import { createElement } from "lwc";
import ContractServiceEdit from "c/contractServiceEdit";

jest.mock(
  "lightning/actions",
  () => ({ CloseActionScreenEvent: class CloseActionScreenEvent {} }),
  { virtual: true }
);
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
  () => ({ __esModule: true, default: false }),
  { virtual: true }
);

describe("contractServiceEdit without Loop_08 (Core 3.4.1)", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("does not offer the edit form without 08", async () => {
    const element = createElement("c-contract-service-edit", {
      is: ContractServiceEdit
    });
    element.recordId = "a0S000000000001AAA";
    document.body.appendChild(element);
    await Promise.resolve();

    expect(element.shadowRoot.textContent).toContain(
      "契約サービスを編集する権限がありません。"
    );
    expect(
      element.shadowRoot.querySelector("lightning-input")
    ).toBeNull();
  });
});
