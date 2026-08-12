import {
  WIZARD_ACTIONS,
  createInitialWizardState,
  reduceWizardState,
  buildPresetKey,
  buildWizardDataFromPreset,
  canLeaveCurrentStep,
  shouldLoadPreset,
  createRowId
} from "c/estimateWizardState";

const dispatch = (state, action) => reduceWizardState(state, action);

/** タイプ依存の入力が一通り埋まった状態を作る（入口 New 確定後）。 */
function filledState() {
  let state = createInitialWizardState();
  state = dispatch(state, {
    type: WIZARD_ACTIONS.SET_ENTRY_MODE,
    entryMode: "new"
  });
  state = dispatch(state, { type: WIZARD_ACTIONS.SET_STEP, step: 2 });
  state = dispatch(state, {
    type: WIZARD_ACTIONS.MERGE_STEP2,
    fields: {
      contractServiceName: "サービスA",
      contractHistoryName: "2026年度 契約",
      contractServiceId: "svcA",
      contractHistoryId: "hisA",
      billingAccountId: "acc1",
      contractServiceCustomFields: { Memo__c: "S" },
      contractHistoryCustomFields: { Memo__c: "H" }
    }
  });
  state = dispatch(state, {
    type: WIZARD_ACTIONS.MERGE_STEP3,
    fields: {
      contractStartDate: "2026-04-01",
      contractEndDate: "2027-03-31",
      contractEffectiveDate: "2026-04-01",
      selectedProducts: [{ rowId: "r1", productId: "p1" }],
      estimateRemarks: "備考テキスト"
    }
  });
  return state;
}

describe("初期状態", () => {
  it("Step1 / 入口未選択 / 契約特定未マウント / 非同期なしで始まる", () => {
    const state = createInitialWizardState();
    expect(state.step).toBe(1);
    expect(state.data.selectedType).toBe("");
    expect(state.data.entryMode).toBe("");
    expect(state.data.contractEndDate).toBe("");
    expect(state.ui.step2Mounted).toBe(false);
    expect(state.ui.step3Mounted).toBe(false);
    expect(canLeaveCurrentStep(state)).toBe(true);
  });

  it("未知のアクションでは状態が変わらない", () => {
    const state = createInitialWizardState();
    expect(dispatch(state, { type: "UNKNOWN" })).toBe(state);
    expect(dispatch(state, null)).toBe(state);
  });
});

describe("SET_STEP", () => {
  it("到達した Step は以後もマウント済みのまま保持される", () => {
    let state = createInitialWizardState();
    state = dispatch(state, { type: WIZARD_ACTIONS.SET_STEP, step: 2 });
    expect(state.ui.step2Mounted).toBe(true);
    expect(state.ui.step3Mounted).toBe(true);

    state = dispatch(state, { type: WIZARD_ACTIONS.SET_STEP, step: 1 });
    expect(state.step).toBe(1);
    expect(state.ui.step2Mounted).toBe(true);
    expect(state.ui.step3Mounted).toBe(true);
  });

  it("Step を往復しても入力値は保持される", () => {
    let state = filledState();
    state = dispatch(state, { type: WIZARD_ACTIONS.SET_STEP, step: 1 });
    state = dispatch(state, { type: WIZARD_ACTIONS.SET_STEP, step: 2 });
    expect(state.data.contractHistoryName).toBe("2026年度 契約");
    expect(state.data.contractStartDate).toBe("2026-04-01");
    expect(state.data.selectedProducts).toHaveLength(1);
  });

  it("範囲外の Step は無視する", () => {
    const state = createInitialWizardState();
    expect(dispatch(state, { type: WIZARD_ACTIONS.SET_STEP, step: 0 })).toBe(
      state
    );
    expect(dispatch(state, { type: WIZARD_ACTIONS.SET_STEP, step: 3 })).toBe(
      state
    );
  });
});

describe("SET_TYPE", () => {
  it("タイプ依存の入力を名前も含めてすべて初期化する", () => {
    const before = filledState();
    const after = dispatch(before, {
      type: WIZARD_ACTIONS.SET_TYPE,
      selectedType: "Change"
    });

    expect(after.data.selectedType).toBe("Change");
    expect(after.data.contractServiceName).toBe("");
    expect(after.data.contractHistoryName).toBe("");
    expect(after.data.contractServiceId).toBe("");
    expect(after.data.contractHistoryId).toBe("");
    expect(after.data.contractStartDate).toBe("");
    expect(after.data.contractEndDate).toBe("");
    expect(after.data.contractEffectiveDate).toBe("");
    expect(after.data.selectedProducts).toEqual([]);
    expect(after.data.changeSourceProducts).toEqual([]);
    expect(after.data.estimateRemarks).toBe("");
    expect(after.data.billingAccountId).toBe("");
    expect(after.data.contractServiceCustomFields).toEqual({});
    expect(after.data.contractHistoryCustomFields).toEqual({});
  });

  it("商談由来の情報はタイプ変更でも保持する", () => {
    let state = createInitialWizardState();
    state = dispatch(state, {
      type: WIZARD_ACTIONS.MERGE_STEP2,
      fields: { opportunityName: "商談X", accountName: "取引先Y" }
    });
    state = dispatch(state, {
      type: WIZARD_ACTIONS.SET_TYPE,
      selectedType: "Renew"
    });
    expect(state.data.opportunityName).toBe("商談X");
    expect(state.data.accountName).toBe("取引先Y");
  });

  it("タイプ変更で詳細パネルを再マウント対象に戻す", () => {
    const before = filledState();
    const after = dispatch(before, {
      type: WIZARD_ACTIONS.SET_TYPE,
      selectedType: "Cancel"
    });
    expect(after.ui.step2Mounted).toBe(true);
    expect(after.ui.step3Mounted).toBe(false);
  });

  it("タイプ変更で loadingStep3 を解除する", () => {
    let state = filledState();
    state = dispatch(state, {
      type: WIZARD_ACTIONS.SET_STEP3_LOADING,
      loading: true
    });
    expect(state.async.loadingStep3).toBe(true);
    state = dispatch(state, {
      type: WIZARD_ACTIONS.SET_TYPE,
      selectedType: "Renew"
    });
    expect(state.async.loadingStep3).toBe(false);
    expect(canLeaveCurrentStep(state)).toBe(true);
  });

  it("同じタイプなら状態を変えない", () => {
    const before = filledState();
    const after = dispatch(before, {
      type: WIZARD_ACTIONS.SET_TYPE,
      selectedType: "New"
    });
    expect(after).toBe(before);
  });

  it("New → Change → New で前タイプの入力が復活しない", () => {
    let state = filledState();
    state = dispatch(state, {
      type: WIZARD_ACTIONS.SET_TYPE,
      selectedType: "Change"
    });
    state = dispatch(state, {
      type: WIZARD_ACTIONS.SET_TYPE,
      selectedType: "New"
    });
    expect(state.data.contractHistoryName).toBe("");
    expect(state.data.selectedProducts).toEqual([]);
  });

  it("サービス選択後の操作選択では契約サービスを維持する", () => {
    let state = createInitialWizardState();
    state = dispatch(state, {
      type: WIZARD_ACTIONS.SET_ENTRY_MODE,
      entryMode: "continuation"
    });
    expect(state.data.selectedType).toBe("");
    state = dispatch(state, {
      type: WIZARD_ACTIONS.SELECT_CONTRACT_SERVICE_START,
      contractServiceId: "svc1",
      contractServiceName: "継続サービス",
      serviceLifecycle: "Term"
    });
    state = dispatch(state, {
      type: WIZARD_ACTIONS.SET_TYPE,
      selectedType: "Change"
    });
    expect(state.data.selectedType).toBe("Change");
    expect(state.data.contractServiceId).toBe("svc1");
    expect(state.data.serviceLifecycle).toBe("Term");
    state = dispatch(state, {
      type: WIZARD_ACTIONS.SET_TYPE,
      selectedType: "Renew"
    });
    expect(state.data.selectedType).toBe("Renew");
    expect(state.data.contractServiceId).toBe("svc1");
  });
});

describe("SET_OPPORTUNITY", () => {
  it("商談から取得した名前を取り込む", () => {
    const state = dispatch(createInitialWizardState(), {
      type: WIZARD_ACTIONS.SET_OPPORTUNITY,
      opportunityName: "商談X",
      accountName: "取引先Y"
    });
    expect(state.data.opportunityName).toBe("商談X");
    expect(state.data.accountName).toBe("取引先Y");
  });

  it("空値でプリセット由来の名前を消さない", () => {
    const loaded = dispatch(createInitialWizardState(), {
      type: WIZARD_ACTIONS.SET_OPPORTUNITY,
      opportunityName: "商談X",
      accountName: "取引先Y"
    });
    const after = dispatch(loaded, {
      type: WIZARD_ACTIONS.SET_OPPORTUNITY,
      opportunityName: "",
      accountName: ""
    });
    expect(after).toBe(loaded);
  });

  it("同じ値なら状態を変えない", () => {
    const loaded = dispatch(createInitialWizardState(), {
      type: WIZARD_ACTIONS.SET_OPPORTUNITY,
      opportunityName: "商談X",
      accountName: "取引先Y"
    });
    const after = dispatch(loaded, {
      type: WIZARD_ACTIONS.SET_OPPORTUNITY,
      opportunityName: "商談X",
      accountName: "取引先Y"
    });
    expect(after).toBe(loaded);
  });
});

describe("MERGE_STEP2", () => {
  it("契約サービスが変わると依存する明細・期間・備考を破棄する", () => {
    const before = filledState();
    const after = dispatch(before, {
      type: WIZARD_ACTIONS.MERGE_STEP2,
      fields: { contractServiceId: "svcB", contractHistoryId: "hisB" }
    });

    expect(after.data.contractServiceId).toBe("svcB");
    expect(after.data.contractHistoryId).toBe("hisB");
    expect(after.data.selectedProducts).toEqual([]);
    expect(after.data.contractStartDate).toBe("");
    expect(after.data.contractEndDate).toBe("");
    expect(after.data.estimateRemarks).toBe("");
    expect(after.data.contractServiceCustomFields).toEqual({});
    expect(after.data.contractHistoryCustomFields).toEqual({});
  });

  it("履歴だけが変わった場合もサービスの追加項目を破棄する（旧契約由来のため）", () => {
    const before = filledState();
    const after = dispatch(before, {
      type: WIZARD_ACTIONS.MERGE_STEP2,
      fields: {
        contractHistoryId: "hisB",
        contractServiceCustomFields: { Memo__c: "S" }
      }
    });
    expect(after.data.contractServiceCustomFields).toEqual({});
    expect(after.data.contractHistoryCustomFields).toEqual({});
    expect(after.data.selectedProducts).toEqual([]);
  });

  it("契約が変わらない入力は単純に取り込む", () => {
    const before = filledState();
    const after = dispatch(before, {
      type: WIZARD_ACTIONS.MERGE_STEP2,
      fields: { contractHistoryName: "別名" }
    });
    expect(after.data.contractHistoryName).toBe("別名");
    expect(after.data.selectedProducts).toHaveLength(1);
    expect(after.data.contractStartDate).toBe("2026-04-01");
  });

  it("serviceLifecycle だけの補完は明細を捨てない", () => {
    const before = filledState();
    const after = dispatch(before, {
      type: WIZARD_ACTIONS.MERGE_STEP2,
      fields: { serviceLifecycle: "Term" }
    });
    expect(after.data.serviceLifecycle).toBe("Term");
    expect(after.data.selectedProducts).toHaveLength(1);
    expect(after.data.contractServiceId).toBe(before.data.contractServiceId);
  });
});

describe("プリセット読込", () => {
  const preset = {
    selectedType: "Change",
    opportunityName: "商談Z",
    contractServiceName: "サービスZ",
    contractHistoryName: "履歴Z",
    contractServiceId: "svcZ",
    contractHistoryId: "hisZ",
    selectedProducts: [{ rowId: "p1" }],
    contractServiceCustomFields: { Memo__c: null }
  };

  it("成功時は状態全体をプリセットで置き換え Step1 に戻す", () => {
    const key = buildPresetKey("hisZ", "edit");
    let state = filledState();
    state = dispatch(state, { type: WIZARD_ACTIONS.PRESET_LOAD_START, key });
    expect(state.async.loadingPreset).toBe(true);
    expect(canLeaveCurrentStep(state)).toBe(false);

    state = dispatch(state, {
      type: WIZARD_ACTIONS.PRESET_LOAD_SUCCESS,
      preset,
      key
    });
    expect(state.step).toBe(1);
    expect(state.data.selectedType).toBe("Change");
    expect(state.data.contractServiceId).toBe("svcZ");
    expect(state.async.loadingPreset).toBe(false);
    expect(shouldLoadPreset(state, key)).toBe(false);
  });

  it("プリセットの null 値はキーごと保持する（デフォルト注入を防ぐ）", () => {
    const data = buildWizardDataFromPreset(preset);
    expect(
      Object.prototype.hasOwnProperty.call(
        data.contractServiceCustomFields,
        "Memo__c"
      )
    ).toBe(true);
    expect(data.contractServiceCustomFields.Memo__c).toBeNull();
  });

  it("Apex の endDate を contractEndDate へ取り込む", () => {
    const data = buildWizardDataFromPreset({
      ...preset,
      endDate: "2027-12-31"
    });
    expect(data.contractEndDate).toBe("2027-12-31");
    expect(data.endDate).toBeUndefined();
  });

  it("失敗時は初期状態に戻し、同じキーでは自動再試行しない", () => {
    const key = buildPresetKey("hisZ", "copy");
    let state = createInitialWizardState();
    state = dispatch(state, { type: WIZARD_ACTIONS.PRESET_LOAD_START, key });
    state = dispatch(state, {
      type: WIZARD_ACTIONS.PRESET_LOAD_FAILURE,
      key,
      message: "読み込みに失敗しました。"
    });

    expect(state.step).toBe(1);
    expect(state.data.selectedType).toBe("");
    expect(state.data.entryMode).toBe("");
    expect(state.async.loadingPreset).toBe(false);
    expect(state.async.presetError).toBe("読み込みに失敗しました。");
    expect(shouldLoadPreset(state, key)).toBe(false);
    expect(shouldLoadPreset(state, buildPresetKey("other", "copy"))).toBe(true);
  });

  it("PRESET_CLEAR_FAILURE で手動再読み込みを許可する", () => {
    const key = buildPresetKey("hisZ", "edit");
    let state = createInitialWizardState();
    state = dispatch(state, {
      type: WIZARD_ACTIONS.PRESET_LOAD_FAILURE,
      key,
      message: "失敗"
    });
    expect(shouldLoadPreset(state, key)).toBe(false);

    state = dispatch(state, { type: WIZARD_ACTIONS.PRESET_CLEAR_FAILURE });
    expect(state.async.presetError).toBe("");
    expect(state.async.failedPresetKey).toBe("");
    expect(shouldLoadPreset(state, key)).toBe(true);
  });

  it("読込中は同じプリセットを二重に読み込まない", () => {
    const key = buildPresetKey("hisZ", "edit");
    const state = dispatch(createInitialWizardState(), {
      type: WIZARD_ACTIONS.PRESET_LOAD_START,
      key
    });
    expect(shouldLoadPreset(state, key)).toBe(false);
  });
});

describe("契約サービスの選択（非同期）", () => {
  /** filledState は New なので、非New に切り替えてから契約を選び直す。 */
  function changeTypeState() {
    return dispatch(filledState(), {
      type: WIZARD_ACTIONS.SET_TYPE,
      selectedType: "Change"
    });
  }

  const historyA = {
    historyId: "hisA",
    historyName: "履歴A",
    version: 2,
    nextVersion: 3,
    renewEligible: true
  };
  const historyB = {
    historyId: "hisB",
    historyName: "履歴B",
    version: 5,
    nextVersion: 6,
    renewEligible: false
  };

  it("選択した時点で契約サービスが反映され、応答を待たずに読込中になる", () => {
    const state = dispatch(changeTypeState(), {
      type: WIZARD_ACTIONS.SELECT_CONTRACT_SERVICE_START,
      contractServiceId: "svcA",
      contractServiceName: "サービスA"
    });
    expect(state.data.contractServiceId).toBe("svcA");
    expect(state.data.contractServiceName).toBe("サービスA");
    expect(state.data.contractHistoryId).toBe("");
    expect(state.async.loadingContractHistory).toBe(true);
    expect(canLeaveCurrentStep(state)).toBe(false);
  });

  it("応答が届くと契約履歴が反映され、読込中が解除される", () => {
    let state = dispatch(changeTypeState(), {
      type: WIZARD_ACTIONS.SELECT_CONTRACT_SERVICE_START,
      contractServiceId: "svcA"
    });
    state = dispatch(state, {
      type: WIZARD_ACTIONS.SELECT_CONTRACT_SERVICE_SUCCESS,
      requestId: state.async.serviceRequestId,
      result: historyA
    });
    expect(state.data.contractHistoryId).toBe("hisA");
    expect(state.data.autoHistoryName).toBe("履歴A");
    expect(state.data.baseHistoryVersion).toBe(2);
    expect(state.data.nextHistoryVersion).toBe(3);
    expect(state.data.renewEligible).toBe(true);
    expect(canLeaveCurrentStep(state)).toBe(true);
  });

  it("A→B と素早く切り替えたとき、遅れて届いた A の応答を採用しない", () => {
    let state = dispatch(changeTypeState(), {
      type: WIZARD_ACTIONS.SELECT_CONTRACT_SERVICE_START,
      contractServiceId: "svcA"
    });
    const requestA = state.async.serviceRequestId;

    state = dispatch(state, {
      type: WIZARD_ACTIONS.SELECT_CONTRACT_SERVICE_START,
      contractServiceId: "svcB"
    });
    const requestB = state.async.serviceRequestId;

    // B の応答が先に届く
    state = dispatch(state, {
      type: WIZARD_ACTIONS.SELECT_CONTRACT_SERVICE_SUCCESS,
      requestId: requestB,
      result: historyB
    });
    // 遅れて A の応答が届く
    const after = dispatch(state, {
      type: WIZARD_ACTIONS.SELECT_CONTRACT_SERVICE_SUCCESS,
      requestId: requestA,
      result: historyA
    });

    expect(after).toBe(state);
    expect(after.data.contractServiceId).toBe("svcB");
    expect(after.data.contractHistoryId).toBe("hisB");
    expect(after.data.baseHistoryVersion).toBe(5);
  });

  it("古いリクエストの失敗応答で最新の状態を壊さない", () => {
    let state = dispatch(changeTypeState(), {
      type: WIZARD_ACTIONS.SELECT_CONTRACT_SERVICE_START,
      contractServiceId: "svcA"
    });
    const requestA = state.async.serviceRequestId;
    state = dispatch(state, {
      type: WIZARD_ACTIONS.SELECT_CONTRACT_SERVICE_START,
      contractServiceId: "svcB"
    });
    state = dispatch(state, {
      type: WIZARD_ACTIONS.SELECT_CONTRACT_SERVICE_SUCCESS,
      requestId: state.async.serviceRequestId,
      result: historyB
    });

    const after = dispatch(state, {
      type: WIZARD_ACTIONS.SELECT_CONTRACT_SERVICE_FAILURE,
      requestId: requestA
    });
    expect(after).toBe(state);
    expect(after.data.contractHistoryId).toBe("hisB");
  });

  it("契約サービスを外すと読込は始まらない", () => {
    const state = dispatch(changeTypeState(), {
      type: WIZARD_ACTIONS.SELECT_CONTRACT_SERVICE_START,
      contractServiceId: ""
    });
    expect(state.data.contractServiceId).toBe("");
    expect(state.async.loadingContractHistory).toBe(false);
    expect(canLeaveCurrentStep(state)).toBe(true);
  });

  it("選択時点で旧契約の明細・期間・備考を破棄する", () => {
    const before = changeTypeState();
    const withProducts = dispatch(before, {
      type: WIZARD_ACTIONS.MERGE_STEP3,
      fields: {
        selectedProducts: [{ rowId: "r1" }],
        contractStartDate: "2026-04-01",
        estimateRemarks: "旧備考"
      }
    });
    const after = dispatch(withProducts, {
      type: WIZARD_ACTIONS.SELECT_CONTRACT_SERVICE_START,
      contractServiceId: "svcB"
    });
    expect(after.data.selectedProducts).toEqual([]);
    expect(after.data.contractStartDate).toBe("");
    expect(after.data.estimateRemarks).toBe("");
  });
});

describe("New の派生値の不変条件", () => {
  it("New では常に作成Version 1・ベースVersionなし・Renew判定なし", () => {
    let state = dispatch(createInitialWizardState(), {
      type: WIZARD_ACTIONS.SET_ENTRY_MODE,
      entryMode: "new"
    });
    state = dispatch(state, {
      type: WIZARD_ACTIONS.MERGE_STEP2,
      fields: {
        baseHistoryVersion: 9,
        nextHistoryVersion: 9,
        renewEligible: true
      }
    });
    expect(state.data.baseHistoryVersion).toBeNull();
    expect(state.data.nextHistoryVersion).toBe(1);
    expect(state.data.renewEligible).toBeNull();
  });

  it("New 以外では取得した値をそのまま保持する", () => {
    let state = dispatch(createInitialWizardState(), {
      type: WIZARD_ACTIONS.SET_TYPE,
      selectedType: "Renew"
    });
    state = dispatch(state, {
      type: WIZARD_ACTIONS.MERGE_STEP2,
      fields: {
        baseHistoryVersion: 9,
        nextHistoryVersion: 10,
        renewEligible: true
      }
    });
    expect(state.data.baseHistoryVersion).toBe(9);
    expect(state.data.nextHistoryVersion).toBe(10);
    expect(state.data.renewEligible).toBe(true);
  });
});

describe("非同期ゲート", () => {
  it("Step3 の商品・日付の読込中は次へ・保存に進めない", () => {
    let state = dispatch(createInitialWizardState(), {
      type: WIZARD_ACTIONS.SET_STEP3_LOADING,
      loading: true
    });
    expect(canLeaveCurrentStep(state)).toBe(false);

    state = dispatch(state, {
      type: WIZARD_ACTIONS.SET_STEP3_LOADING,
      loading: false
    });
    expect(canLeaveCurrentStep(state)).toBe(true);
  });

  it("保存中は次へ・保存に進めない", () => {
    let state = dispatch(createInitialWizardState(), {
      type: WIZARD_ACTIONS.SAVE_START
    });
    expect(state.async.saving).toBe(true);
    expect(canLeaveCurrentStep(state)).toBe(false);

    state = dispatch(state, { type: WIZARD_ACTIONS.SAVE_END });
    expect(canLeaveCurrentStep(state)).toBe(true);
  });
});

describe("MERGE_STEP3", () => {
  it("日付・備考・商品明細を親状態へ取り込む", () => {
    const state = dispatch(createInitialWizardState(), {
      type: WIZARD_ACTIONS.MERGE_STEP3,
      fields: {
        contractStartDate: "2026-04-01",
        contractEndDate: "2027-03-31",
        contractEffectiveDate: "2026-04-01",
        contractHistoryName: "履歴名",
        estimateRemarks: "備考",
        selectedProducts: [{ id: "row-a", productId: "p1" }]
      }
    });
    expect(state.data.contractStartDate).toBe("2026-04-01");
    expect(state.data.contractEndDate).toBe("2027-03-31");
    // 契約履歴名は基本情報（MERGE_STEP2）専用。詳細からは取り込まない。
    expect(state.data.contractHistoryName).toBe("");
    expect(state.data.estimateRemarks).toBe("備考");
    expect(state.data.selectedProducts).toEqual([
      { id: "row-a", productId: "p1" }
    ]);
  });

  it("旧キー endDate を contractEndDate へエイリアスする", () => {
    const state = dispatch(createInitialWizardState(), {
      type: WIZARD_ACTIONS.MERGE_STEP3,
      fields: {
        endDate: "2027-03-31"
      }
    });
    expect(state.data.contractEndDate).toBe("2027-03-31");
    expect(state.data.endDate).toBeUndefined();
  });

  it("contractEndDate と endDate が両方ある場合は contractEndDate を優先する", () => {
    const state = dispatch(createInitialWizardState(), {
      type: WIZARD_ACTIONS.MERGE_STEP3,
      fields: {
        contractEndDate: "2027-03-31",
        endDate: "2099-12-31"
      }
    });
    expect(state.data.contractEndDate).toBe("2027-03-31");
  });

  it("未知のキーは無視する", () => {
    const before = createInitialWizardState();
    const after = dispatch(before, {
      type: WIZARD_ACTIONS.MERGE_STEP3,
      fields: {
        selectedType: "Cancel",
        contractServiceId: "should-ignore",
        unknownField: "x"
      }
    });
    expect(after).toBe(before);
    expect(after.data.selectedType).toBe("");
    expect(after.data.contractServiceId).toBe("");
  });

  it("契約サービス／履歴の追加項目を取り込む", () => {
    const state = dispatch(createInitialWizardState(), {
      type: WIZARD_ACTIONS.MERGE_STEP3,
      fields: {
        contractServiceCustomFields: { Memo__c: "S" },
        contractHistoryCustomFields: { ApplicationDate__c: "2026-04-01" },
        serviceCustomFieldsExpanded: true,
        historyCustomFieldsExpanded: true
      }
    });
    expect(state.data.contractServiceCustomFields).toEqual({ Memo__c: "S" });
    expect(state.data.contractHistoryCustomFields).toEqual({
      ApplicationDate__c: "2026-04-01"
    });
    expect(state.data.serviceCustomFieldsExpanded).toBe(true);
    expect(state.data.historyCustomFieldsExpanded).toBe(true);
  });

  it("契約サービス変更後に Step3 が書き通した新明細で上書きできる", () => {
    let state = filledState();
    state = dispatch(state, {
      type: WIZARD_ACTIONS.SET_TYPE,
      selectedType: "Change"
    });
    state = dispatch(state, {
      type: WIZARD_ACTIONS.SELECT_CONTRACT_SERVICE_START,
      contractServiceId: "svcB"
    });
    expect(state.data.selectedProducts).toEqual([]);

    state = dispatch(state, {
      type: WIZARD_ACTIONS.MERGE_STEP3,
      fields: {
        selectedProducts: [{ id: "row-new", productId: "p9" }],
        contractStartDate: "2026-05-01",
        endDate: "2027-04-30"
      }
    });
    expect(state.data.selectedProducts).toEqual([
      { id: "row-new", productId: "p9" }
    ]);
    expect(state.data.contractStartDate).toBe("2026-05-01");
    expect(state.data.contractEndDate).toBe("2027-04-30");
  });
});

describe("商品明細行の ID", () => {
  it("連続発行しても重複しない", () => {
    const ids = new Set();
    for (let i = 0; i < 1000; i++) {
      ids.add(createRowId());
    }
    expect(ids.size).toBe(1000);
  });

  it("既存の row-N 形式の ID と衝突しない", () => {
    // 途中の行を削除した明細（row-1, row-3）を読み直しても、
    // 追加行が row-3 と重ならないこと。
    const existing = new Set(["row-1", "row-2", "row-3"]);
    for (let i = 0; i < 100; i++) {
      expect(existing.has(createRowId())).toBe(false);
    }
  });
});

describe("不変性", () => {
  it("遷移は元の state を書き換えない", () => {
    const before = filledState();
    const snapshot = JSON.stringify(before);
    dispatch(before, { type: WIZARD_ACTIONS.SET_TYPE, selectedType: "Renew" });
    dispatch(before, {
      type: WIZARD_ACTIONS.MERGE_STEP2,
      fields: { contractServiceId: "svcB" }
    });
    expect(JSON.stringify(before)).toBe(snapshot);
  });
});
