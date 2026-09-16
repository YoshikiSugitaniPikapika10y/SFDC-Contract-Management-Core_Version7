const mockNavigate = Symbol.for("NavigationMixin.Navigate");
const mockGetRecordNotifyChange = jest.fn();
const mockGetLightningBase = jest.fn(() => "https://example.my.salesforce.com");

jest.mock(
  "lightning/navigation",
  () => {
    const NavigationMixin = (Base) => class extends Base {};
    NavigationMixin.Navigate = Symbol.for("NavigationMixin.Navigate");
    NavigationMixin.GenerateUrl = Symbol.for("NavigationMixin.GenerateUrl");
    return { NavigationMixin };
  },
  { virtual: true }
);

jest.mock(
  "lightning/uiRecordApi",
  () => ({
    getRecordNotifyChange: (...args) => mockGetRecordNotifyChange(...args)
  }),
  { virtual: true }
);

jest.mock("c/estimateWizardNavigation", () => ({
  getLightningBase: (...args) => mockGetLightningBase(...args)
}));

import {
  buildOrderWizardUrls,
  closeOrderWizardTab,
  initializeOrderWizardFromUrl,
  isOrderWizardTabView,
  navigateToContractHistoryRecord,
  navigateToOrderWizard,
  openContentDocumentFilePreview,
  readOrderWizardRecordId
} from "c/orderWizardNavigation";

describe("orderWizardNavigation", () => {
  beforeEach(() => {
    mockGetRecordNotifyChange.mockReset();
    mockGetLightningBase.mockReset().mockReturnValue(
      "https://example.my.salesforce.com"
    );
    window.history.replaceState({}, "", "/lightning/page/home");
    window.close = jest.fn();
  });

  test.each([
    [
      "order",
      {
        type: "standard__navItemPage",
        attributes: { apiName: "Order_Process" }
      }
    ],
    [
      "revert",
      {
        type: "standard__component",
        attributes: { componentName: "c__orderRevertWizard" }
      }
    ],
    [
      "preview",
      {
        type: "standard__navItemPage",
        attributes: { apiName: "Order_Invoice_Preview" }
      }
    ]
  ])("%sの正規ページ参照を対象タブと判定する", (token, pageRef) => {
    expect(isOrderWizardTabView(pageRef, token)).toBe(true);
  });

  test("対象外・空・別コンポーネントを受注タブと誤認しない", () => {
    expect(isOrderWizardTabView(null, "order")).toBe(false);
    expect(
      isOrderWizardTabView(
        {
          type: "standard__component",
          attributes: { componentName: "c__otherComponent" }
        },
        "order"
      )
    ).toBe(false);
    expect(isOrderWizardTabView({}, "unknown")).toBe(false);
  });

  test("現在URLのナビ項目・コンポーネント形式も判定する", () => {
    window.history.replaceState({}, "", "/lightning/n/Order_Revert");
    expect(isOrderWizardTabView({}, "revert")).toBe(true);

    window.history.replaceState(
      {},
      "",
      "/lightning/cmp/c__orderInvoicePreviewWizard"
    );
    expect(isOrderWizardTabView({}, "preview")).toBe(true);
  });

  test("ページ状態とURLから契約履歴IDを安全に読む", () => {
    expect(
      readOrderWizardRecordId({ state: { c__recordId: "a01AAA" } })
    ).toBe("a01AAA");
    expect(readOrderWizardRecordId(null)).toBe("");

    const component = {};
    window.history.replaceState(
      {},
      "",
      "/lightning/n/Order_Process?c__recordId=a01URL"
    );
    initializeOrderWizardFromUrl(component);
    expect(component.recordId).toBe("a01URL");

    window.history.replaceState({}, "", "/lightning/n/Order_Process");
    initializeOrderWizardFromUrl(component);
    expect(component.recordId).toBe("a01URL");
  });

  test("3種類のウィザードURLをコンポーネント・ナビ項目の順で組み立てる", () => {
    expect(buildOrderWizardUrls({ wizardKey: "unknown", recordId: "a01" })).toEqual(
      []
    );
    expect(buildOrderWizardUrls({ wizardKey: "order" })).toEqual([]);

    expect(
      buildOrderWizardUrls({ wizardKey: "revert", recordId: "a01 A&B" })
    ).toEqual([
      "https://example.my.salesforce.com/lightning/cmp/c__orderRevertWizard?c__recordId=a01+A%26B",
      "https://example.my.salesforce.com/lightning/n/Order_Revert?c__recordId=a01+A%26B"
    ]);
  });

  test("受注ウィザードへ正規pageRefで遷移し、対象不足は拒否する", () => {
    const navigate = jest.fn();
    const component = { [mockNavigate]: navigate };

    navigateToOrderWizard(component, {
      wizardKey: "order",
      recordId: "a01AAA"
    });

    expect(navigate).toHaveBeenCalledWith({
      type: "standard__component",
      attributes: { componentName: "c__orderCreateWizard" },
      state: { c__recordId: "a01AAA" }
    });
    expect(() =>
      navigateToOrderWizard(component, {
        wizardKey: "unknown",
        recordId: "a01AAA"
      })
    ).toThrow("ORDER_WIZARD_TARGET_MISSING");
    expect(() =>
      navigateToOrderWizard(component, { wizardKey: "order" })
    ).toThrow("ORDER_WIZARD_TARGET_MISSING");
  });

  test("契約履歴詳細へ戻し、IDまたはNavigateが無ければ何もしない", () => {
    const navigate = jest.fn();
    navigateToContractHistoryRecord(
      { recordId: "a01HOST", [mockNavigate]: navigate },
      null
    );
    expect(navigate).toHaveBeenCalledWith({
      type: "standard__recordPage",
      attributes: {
        recordId: "a01HOST",
        objectApiName: "ContractHistory__c",
        actionName: "view"
      }
    });

    navigate.mockClear();
    navigateToContractHistoryRecord({ [mockNavigate]: navigate }, null);
    navigateToContractHistoryRecord({ recordId: "a01HOST" }, null);
    expect(navigate).not.toHaveBeenCalled();
  });

  test("閉じる際は必要なレコードだけ通知し、詳細へ戻す", () => {
    const navigate = jest.fn();
    const component = { recordId: "a01HOST", [mockNavigate]: navigate };

    closeOrderWizardTab(component);
    expect(mockGetRecordNotifyChange).toHaveBeenCalledWith([
      { recordId: "a01HOST" }
    ]);
    expect(navigate).toHaveBeenCalledTimes(1);
    expect(window.close).not.toHaveBeenCalled();

    mockGetRecordNotifyChange.mockClear();
    navigate.mockClear();
    closeOrderWizardTab(component, { refresh: false, recordId: "a01ARG" });
    expect(mockGetRecordNotifyChange).not.toHaveBeenCalled();
    expect(navigate.mock.calls[0][0].attributes.recordId).toBe("a01ARG");
  });

  test("戻り先IDが無い場合だけ現在タブを閉じる", () => {
    closeOrderWizardTab({});
    expect(window.close).toHaveBeenCalledTimes(1);
    expect(mockGetRecordNotifyChange).not.toHaveBeenCalled();
  });

  test("Filesプレビューは標準filePreviewへ対象IDを1件渡す", () => {
    const navigate = jest.fn();
    const component = { [mockNavigate]: navigate };

    openContentDocumentFilePreview(component, 123);
    expect(navigate).toHaveBeenCalledWith({
      type: "standard__namedPage",
      attributes: { pageName: "filePreview" },
      state: { recordIds: "123", selectedRecordId: "123" }
    });

    navigate.mockClear();
    openContentDocumentFilePreview(component, null);
    openContentDocumentFilePreview({}, "069AAA");
    expect(navigate).not.toHaveBeenCalled();
  });
});
