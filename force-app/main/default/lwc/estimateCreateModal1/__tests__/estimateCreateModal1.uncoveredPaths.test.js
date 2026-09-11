import { createElement } from "lwc";
import EstimateCreateModal1 from "c/estimateCreateModal1";
import {
  getFieldValue,
  getRecordNotifyChange
} from "lightning/uiRecordApi";

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

describe("estimateCreateModal1 uncovered (Core 4.3.3 / 0.1)", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("renders 基本情報 with 取引先／商談 and type 新規／追加変更／更新／解約", async () => {
    const el = createElement("c-estimate-create-modal1", {
      is: EstimateCreateModal1
    });
    el.recordId = "006000000000001AAA";
    el.accountName = "取引先A";
    el.opportunityName = "商談A";
    el.selectedType = "New";
    document.body.appendChild(el);
    await Promise.resolve();
    expect(el.shadowRoot.querySelector(".est-card-title").textContent).toBe(
      "基本情報"
    );
    const labels = [...el.shadowRoot.querySelectorAll(".est-meta-label")].map(
      (n) => n.textContent
    );
    expect(labels).toEqual(["取引先", "商談"]);
    const types = [...el.shadowRoot.querySelectorAll(".est-type-group button")].map(
      (n) => n.textContent.trim()
    );
    expect(types).toEqual(["新規", "追加変更", "更新", "解約"]);
    const active = el.shadowRoot.querySelector(".est-type-btn_active");
    expect(active.textContent.trim()).toBe("新規");
    expect(active.getAttribute("aria-pressed")).toBe("true");
    document.body.removeChild(el);
  });

  it("empty names show — (Core 4.3.3)", async () => {
    const el = createElement("c-estimate-create-modal1", {
      is: EstimateCreateModal1
    });
    document.body.appendChild(el);
    await Promise.resolve();
    const values = [...el.shadowRoot.querySelectorAll(".est-meta-value")].map(
      (n) => n.textContent
    );
    expect(values).toEqual(["—", "—"]);
    document.body.removeChild(el);
  });

  it("Estimate edit cannot change type (Core 4.3)", async () => {
    const el = createElement("c-estimate-create-modal1", {
      is: EstimateCreateModal1
    });
    el.readOnly = true;
    el.selectedType = "Change";
    document.body.appendChild(el);
    await Promise.resolve();
    const buttons = [...el.shadowRoot.querySelectorAll(".est-type-group button")];
    expect(buttons.every((b) => b.disabled)).toBe(true);
    expect(
      el.shadowRoot.querySelector('[data-type="Change"]').className
    ).toContain("est-type-btn_active");
    el.shadowRoot
      .querySelector('[data-type="New"]')
      .dispatchEvent(new CustomEvent("click"));
    await Promise.resolve();
    document.body.removeChild(el);
  });

  it("type button emits typechange with New (Core 0.1)", async () => {
    const el = createElement("c-estimate-create-modal1", {
      is: EstimateCreateModal1
    });
    el.selectedType = "";
    document.body.appendChild(el);
    await Promise.resolve();
    const handler = jest.fn();
    el.addEventListener("typechange", handler);
    el.shadowRoot.querySelector('[data-type="Renew"]').click();
    expect(handler).toHaveBeenCalled();
    expect(handler.mock.calls[0][0].detail.selectedType).toBe("Renew");
    document.body.removeChild(el);
  });

  it("wired opportunity emits opportunityloaded (Core 4.3.3)", () => {
    getFieldValue.mockImplementation((_data, field) => {
      if (field.fieldApiName === "Name") {
        return "商談B";
      }
      if (field.fieldApiName === "Account.Name") {
        return "取引先B";
      }
      if (field.fieldApiName === "ContactId") {
        return "003AAA";
      }
      return "";
    });
    const ctx = {
      dispatchEvent: jest.fn()
    };
    EstimateCreateModal1.prototype.wiredOpportunity.call(ctx, {
      data: { id: "006AAA" }
    });
    expect(ctx.dispatchEvent.mock.calls[0][0].type).toBe("opportunityloaded");
    expect(ctx.dispatchEvent.mock.calls[0][0].detail).toEqual({
      opportunityName: "商談B",
      accountName: "取引先B",
      opportunityContactId: "003AAA"
    });
    EstimateCreateModal1.prototype.wiredOpportunity.call(ctx, { data: null });
    getFieldValue.mockReturnValue("");
    EstimateCreateModal1.prototype.wiredOpportunity.call(ctx, {
      data: { id: "006BBB" }
    });
    expect(ctx.dispatchEvent).toHaveBeenCalledTimes(1);
  });

  it("connectedCallback notifies LDS for the opportunity (Core 4.1)", () => {
    const ctx = { recordId: "006AAA" };
    EstimateCreateModal1.prototype.connectedCallback.call(ctx);
    expect(getRecordNotifyChange).toHaveBeenCalledWith([
      { recordId: "006AAA" }
    ]);
    EstimateCreateModal1.prototype.connectedCallback.call({ recordId: "" });
  });

  it("handleTypeSelect ignores missing type", () => {
    const ctx = {
      readOnly: false,
      dispatchEvent: jest.fn()
    };
    EstimateCreateModal1.prototype.handleTypeSelect.call(ctx, {
      currentTarget: { dataset: {} }
    });
    expect(ctx.dispatchEvent).not.toHaveBeenCalled();
  });
});
