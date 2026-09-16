const GenerateUrl = Symbol.for("NavigationMixin.GenerateUrl");

jest.mock(
  "lightning/navigation",
  () => {
    const NavigationMixin = (Base) => class extends Base {};
    NavigationMixin.Navigate = Symbol.for("NavigationMixin.Navigate");
    NavigationMixin.GenerateUrl = GenerateUrl;
    return { NavigationMixin };
  },
  { virtual: true }
);

import {
  buildEstimateWizardUrl,
  getLightningBase,
  openEstimateWizardTab,
  resolveEstimateWizardUrl,
  toAbsoluteLightningUrl
} from "c/estimateWizardNavigation";

describe("estimateWizardNavigation", () => {
  beforeEach(() => {
    window.history.replaceState({}, "", "/lightning/page/home");
    window.open = jest.fn(() => ({}));
  });

  test("Lightning基点と相対URLを同一Orgの絶対URLへ揃える", () => {
    expect(getLightningBase()).toBe(window.location.origin);
    expect(toAbsoluteLightningUrl("/lightning/n/Estimate_Create")).toBe(
      `${window.location.origin}/lightning/n/Estimate_Create`
    );
    expect(toAbsoluteLightningUrl("lightning/n/Estimate_Create")).toBe(
      `${window.location.origin}/lightning/n/Estimate_Create`
    );
    expect(toAbsoluteLightningUrl("https://example.com/lightning/n/X")).toBe(
      "https://example.com/lightning/n/X"
    );
    expect(toAbsoluteLightningUrl("")).toBe("");
  });

  test("見積新規・コピーの両入口へ同じ状態をURLエンコードして渡す", () => {
    expect(buildEstimateWizardUrl({})).toEqual([]);

    const urls = buildEstimateWizardUrl({
      opportunityId: "006 A&B",
      copyFromHistoryId: "a01/履歴"
    });

    expect(urls).toHaveLength(2);
    expect(urls[0]).toBe(
      `${window.location.origin}/lightning/cmp/c__estimateCreateWizard?c__recordId=006+A%26B&c__copyFromHistoryId=a01%2F%E5%B1%A5%E6%AD%B4`
    );
    expect(urls[1]).toBe(
      `${window.location.origin}/lightning/n/Estimate_Create?c__recordId=006+A%26B&c__copyFromHistoryId=a01%2F%E5%B1%A5%E6%AD%B4`
    );
  });

  test("IDがあれば手組みURLを優先しGenerateUrlを呼ばない", async () => {
    const component = { [GenerateUrl]: jest.fn() };

    const url = await resolveEstimateWizardUrl(component, {
      opportunityId: "006AAA"
    });

    expect(url).toBe(
      `${window.location.origin}/lightning/cmp/c__estimateCreateWizard?c__recordId=006AAA`
    );
    expect(component[GenerateUrl]).not.toHaveBeenCalled();
  });

  test("手組みできない場合はナビ項目からコンポーネントへ順にフォールバックする", async () => {
    const generateUrl = jest
      .fn()
      .mockRejectedValueOnce(new Error("nav item unavailable"))
      .mockResolvedValueOnce("/lightning/cmp/c__estimateCreateWizard");
    const component = { [GenerateUrl]: generateUrl };

    await expect(resolveEstimateWizardUrl(component, {})).resolves.toBe(
      `${window.location.origin}/lightning/cmp/c__estimateCreateWizard`
    );
    expect(generateUrl).toHaveBeenNthCalledWith(
      1,
      expect.objectContaining({
        type: "standard__navItemPage",
        attributes: { apiName: "Estimate_Create" },
        state: {}
      })
    );
    expect(generateUrl).toHaveBeenNthCalledWith(
      2,
      expect.objectContaining({
        type: "standard__component",
        attributes: { componentName: "c__estimateCreateWizard" },
        state: {}
      })
    );
  });

  test("生成手段が無ければ空を返す", async () => {
    await expect(resolveEstimateWizardUrl(null, {})).resolves.toBe("");
    await expect(
      resolveEstimateWizardUrl(
        { [GenerateUrl]: jest.fn().mockResolvedValue("") },
        {}
      )
    ).resolves.toBe("");
  });

  test("手組みURLをnoopenerの別タブで開き、開けなければ明示エラーにする", async () => {
    const expected =
      `${window.location.origin}/lightning/cmp/c__estimateCreateWizard?` +
      "c__copyFromHistoryId=a01AAA";

    await expect(
      openEstimateWizardTab(null, { copyFromHistoryId: "a01AAA" })
    ).resolves.toBe(expected);
    expect(window.open).toHaveBeenCalledWith(
      expected,
      "_blank",
      "noopener,noreferrer"
    );

    window.open.mockReturnValueOnce(null);
    expect(() =>
      openEstimateWizardTab(null, { opportunityId: "006AAA" })
    ).toThrow("POPUP_BLOCKED");
  });

  test("GenerateUrl経路でも別タブを開き、URL無しとポップアップ拒否を区別する", async () => {
    const component = {
      [GenerateUrl]: jest
        .fn()
        .mockResolvedValue("/lightning/n/Estimate_Create")
    };

    await expect(openEstimateWizardTab(component, {})).resolves.toBe(
      `${window.location.origin}/lightning/n/Estimate_Create`
    );

    await expect(openEstimateWizardTab(null, {})).rejects.toThrow(
      "見積ウィザード URL を生成できません。"
    );

    window.open.mockReturnValue(null);
    await expect(openEstimateWizardTab(component, {})).rejects.toThrow(
      "POPUP_BLOCKED"
    );
  });
});
