/**
 * 見積ウィザードの状態と状態遷移を一元管理する純粋モジュール。
 *
 * 設計上の約束:
 *   - 状態を書き換えてよいのは reduceWizardState だけ（呼び出し側でのスプレッドマージ禁止）
 *   - すべての遷移は名前付きアクションとして定義する
 *   - Salesforce / DOM に一切依存しないため、Jest で単体テストできる
 */

import { setAmountCalculationRoundingModes } from "c/estimateLineItemUtils";

export const WIZARD_ACTIONS = {
  /** 新規作成として初期化する */
  INITIALIZE_NEW: "INITIALIZE_NEW",
  /** 編集 / コピーのプリセット読込を開始する */
  PRESET_LOAD_START: "PRESET_LOAD_START",
  /** プリセット読込に成功し、状態全体を置き換える */
  PRESET_LOAD_SUCCESS: "PRESET_LOAD_SUCCESS",
  /** プリセット読込に失敗し、初期状態に戻す（同じキーでは自動再試行しない） */
  PRESET_LOAD_FAILURE: "PRESET_LOAD_FAILURE",
  /** 失敗キーをクリアし、手動再読み込みを許可する */
  PRESET_CLEAR_FAILURE: "PRESET_CLEAR_FAILURE",
  /** 商談から取得した商談名・取引先名を取り込む */
  SET_OPPORTUNITY: "SET_OPPORTUNITY",
  /** 見積タイプを変更し、タイプ依存の入力をまとめて初期化する */
  SET_TYPE: "SET_TYPE",
  /** 入口（新規 / 既存の続き）を変更する */
  SET_ENTRY_MODE: "SET_ENTRY_MODE",
  /** 表示中の Step を変更する */
  SET_STEP: "SET_STEP",
  /** Step2 からの入力を取り込む（契約サービス / 履歴の変更時は依存項目を初期化） */
  MERGE_STEP2: "MERGE_STEP2",
  /** Step3 からの入力を取り込む */
  MERGE_STEP3: "MERGE_STEP3",
  /** Step3 の非同期読込中フラグを更新する */
  SET_STEP3_LOADING: "SET_STEP3_LOADING",
  /** 契約サービスを選択し、依存する入力を即座に初期化して履歴の読込を開始する */
  SELECT_CONTRACT_SERVICE_START: "SELECT_CONTRACT_SERVICE_START",
  /** 契約履歴の読込に成功（最新リクエストの応答のみ採用） */
  SELECT_CONTRACT_SERVICE_SUCCESS: "SELECT_CONTRACT_SERVICE_SUCCESS",
  /** 契約履歴の読込に失敗（最新リクエストの応答のみ採用） */
  SELECT_CONTRACT_SERVICE_FAILURE: "SELECT_CONTRACT_SERVICE_FAILURE",
  /** 保存開始 */
  SAVE_START: "SAVE_START",
  /** 保存終了（成功・失敗を問わない） */
  SAVE_END: "SAVE_END"
};

/**
 * 見積タイプに依存する入力。タイプを変えたらすべて初期化する。
 * 商談名・取引先名は商談由来なのでタイプに依存しない。
 */
const TYPE_DEPENDENT_FIELDS = [
  "contractServiceName",
  "contractHistoryName",
  "contractServiceId",
  "contractHistoryId",
  "contractStartDate",
  "contractEndDate",
  "contractEffectiveDate",
  "autoHistoryName",
  "baseHistoryVersion",
  "nextHistoryVersion",
  "previousTermStartDate",
  "previousTermEndDate",
  "renewEligible",
  "selectedProducts",
  "changeSourceProducts",
  "estimateRemarkMasterId",
  "estimateRemarks",
  "billingAccountId",
  "serviceCustomFieldsExpanded",
  "historyCustomFieldsExpanded",
  "remarksExpanded",
  "contractServiceCustomFields",
  "contractHistoryCustomFields",
  "taxPercent",
  "estimateDate",
  "estimateValidDate",
  "estimateValidDateTouched",
  "serviceLifecycle",
  "estimateSendContactId"
];

/**
 * 契約サービス / 契約履歴に依存する入力。
 * どちらかが変わったら、旧契約由来の明細・期間・備考を持ち越さない。
 */
const CONTRACT_DEPENDENT_FIELDS = [
  "contractStartDate",
  "contractEndDate",
  "contractEffectiveDate",
  "previousTermStartDate",
  "previousTermEndDate",
  "selectedProducts",
  "changeSourceProducts",
  "estimateRemarkMasterId",
  "estimateRemarks",
  "contractHistoryCustomFields",
  "serviceCustomFieldsExpanded",
  "historyCustomFieldsExpanded",
  "estimateDate",
  "estimateValidDate",
  "estimateValidDateTouched",
  "estimateSendContactId"
];

/**
 * Step3 から取り込むフィールドの許可リスト。
 * endDate は contractEndDate への読み取り専用エイリアス（Apex プリセット互換）。
 * Modal3 は contractEndDate のみ emit する。
 */
const STEP3_ALLOWED_FIELDS = [
  "contractStartDate",
  "contractEndDate",
  "endDate",
  "contractEffectiveDate",
  "previousTermStartDate",
  "previousTermEndDate",
  "estimateRemarkMasterId",
  "estimateRemarks",
  "selectedProducts",
  "changeSourceProducts",
  "serviceCustomFieldsExpanded",
  "historyCustomFieldsExpanded",
  "remarksExpanded",
  "contractServiceCustomFields",
  "contractHistoryCustomFields",
  "estimateDate",
  "estimateValidDate",
  "estimateValidDateTouched"
];

export function createEmptyWizardData() {
  return {
    /** 入口選択前は空。new 選択後 New / continuation 選択後は操作選択まで空可 */
    selectedType: "",
    /** new | continuation | "" — 作成開始時は未選択で入口だけ出す */
    entryMode: "",
    /** Term | Spot | "" */
    serviceLifecycle: "",
    opportunityName: "",
    accountName: "",
    contractServiceName: "",
    contractHistoryName: "",
    contractServiceId: "",
    contractHistoryId: "",
    contractStartDate: "",
    contractEndDate: "",
    contractEffectiveDate: "",
    autoHistoryName: "",
    baseHistoryVersion: null,
    nextHistoryVersion: null,
    previousTermStartDate: "",
    previousTermEndDate: "",
    renewEligible: null,
    selectedProducts: [],
    changeSourceProducts: [],
    estimateRemarkMasterId: "",
    estimateRemarks: "",
    billingAccountId: "",
    taxPercent: null,
    historyStatus: "",
    /** 編集時の楽観ロック用（ContractHistory LastModified epoch ms） */
    lastModifiedToken: "",
    serviceCustomFieldsExpanded: true,
    historyCustomFieldsExpanded: true,
    remarksExpanded: true,
    contractServiceCustomFields: {},
    contractHistoryCustomFields: {},
    estimateDate: "",
    estimateValidDate: "",
    estimateValidDateTouched: false,
    estimateSendContactId: "",
    opportunityContactId: "",
    defaultMonthlyCycles: null,
    estimateValidMonths: null,
    estimateSendMode: "",
    taxRoundingMode: null,
    quantityUnitPriceRoundingMode: null,
    amountRoundingMode: null
  };
}

export function createInitialWizardState() {
  return {
    step: 1,
    data: createEmptyWizardData(),
    ui: {
      // step2Mounted = 基本情報の契約特定パネル（旧 modal2）
      // step3Mounted = 詳細情報パネル（旧 modal3）
      // 作成開始は入口のみ。entryMode 確定後に契約特定をマウントする
      step2Mounted: false,
      step3Mounted: false
    },
    async: {
      loadingPreset: false,
      presetError: "",
      /** 読込済みプリセットのキー。同じキーの再読込を防ぐ。 */
      loadedPresetKey: "",
      /** 読込に失敗したプリセットのキー。自動再試行ループを防ぐ。 */
      failedPresetKey: "",
      loadingContractHistory: false,
      /** 契約サービス選択の連番。古い応答を破棄するために使う。 */
      serviceRequestId: 0,
      loadingStep3: false,
      saving: false,
      loadingDocumentDefaults: false
    }
  };
}

export function buildPresetKey(sourceId, mode) {
  return sourceId ? `${mode}:${sourceId}` : "";
}

export function buildWizardDataFromPreset(preset) {
  const empty = createEmptyWizardData();
  if (!preset) {
    return empty;
  }
  const selectedType = preset.selectedType || "New";
  return {
    ...empty,
    selectedType,
    entryMode: selectedType === "New" ? "new" : "continuation",
    serviceLifecycle: preset.serviceLifecycle || "",
    opportunityName: preset.opportunityName || "",
    accountName: preset.accountName || "",
    contractServiceName: preset.contractServiceName || "",
    contractHistoryName: preset.contractHistoryName || "",
    contractServiceId: preset.contractServiceId || "",
    contractHistoryId: preset.contractHistoryId || "",
    contractStartDate: preset.contractStartDate || "",
    // Apex は contractEndDate を正とし、旧 endDate も互換で返す。
    contractEndDate: preset.contractEndDate || preset.endDate || "",
    contractEffectiveDate: preset.contractEffectiveDate || "",
    autoHistoryName: preset.autoHistoryName || "",
    baseHistoryVersion:
      preset.baseHistoryVersion != null ? preset.baseHistoryVersion : null,
    nextHistoryVersion:
      preset.nextHistoryVersion != null ? preset.nextHistoryVersion : null,
    previousTermStartDate: preset.previousTermStartDate || "",
    previousTermEndDate: preset.previousTermEndDate || "",
    renewEligible: preset.renewEligible != null ? preset.renewEligible : null,
    selectedProducts: preset.selectedProducts || [],
    changeSourceProducts: preset.changeSourceProducts || [],
    estimateRemarkMasterId: preset.estimateRemarkMasterId || "",
    estimateRemarks: preset.estimateRemarks || "",
    billingAccountId: preset.billingAccountId || "",
    taxPercent:
      preset.taxPercent == null || preset.taxPercent === ""
        ? selectedType === "New"
          ? 10
          : null
        : Number(preset.taxPercent),
    estimateDate: preset.estimateDate || "",
    estimateValidDate: preset.estimateValidDate || "",
    estimateValidDateTouched: Boolean(preset.estimateValidDate),
    estimateSendContactId: preset.estimateSendContactId || "",
    historyStatus: preset.historyStatus || "",
    lastModifiedToken: preset.lastModifiedToken || "",
    serviceCustomFieldsExpanded: resolveCustomPanelExpanded(
      preset.serviceCustomFieldsExpanded
    ),
    historyCustomFieldsExpanded: resolveCustomPanelExpanded(
      preset.historyCustomFieldsExpanded
    ),
    remarksExpanded: preset.remarksExpanded !== false,
    contractServiceCustomFields: {
      ...(preset.contractServiceCustomFields || {})
    },
    contractHistoryCustomFields: {
      ...(preset.contractHistoryCustomFields || {})
    }
  };
}

/** 契約カスタムはデフォルト開。個別フラグがあればそれ、無ければ開く（旧 Apex の値有無判定は無視）。 */
function resolveCustomPanelExpanded(explicit) {
  if (explicit != null) {
    return explicit !== false;
  }
  return true;
}

/** 指定フィールドだけを初期値に戻した新しい data を返す。 */
function resetFields(data, fieldNames) {
  const empty = createEmptyWizardData();
  const next = { ...data };
  fieldNames.forEach((name) => {
    next[name] = empty[name];
  });
  return next;
}

/**
 * Step 到達済みフラグ。一度到達した Step は破棄せず保持する。
 * 2段階構成: Step1=基本情報（modal1+modal2）、Step2=詳細情報（modal3）
 */
function withMountedSteps(ui, step) {
  return {
    step2Mounted: ui.step2Mounted || step >= 1,
    step3Mounted: ui.step3Mounted || step >= 2
  };
}

const CONTINUATION_OPS = new Set(["Change", "Renew", "Cancel"]);

function reduceSetType(state, action) {
  // 仕様: Core 第4.3節、第4.3.7節。見積種別を変えたら商談と取引先以外を破棄する。
  // 空文字は「続きで操作未選択」として明示的に許可する
  if (!Object.prototype.hasOwnProperty.call(action, "selectedType")) {
    return state;
  }
  const nextType = action.selectedType;
  if (nextType === state.data.selectedType) {
    return state;
  }

  const prevType = state.data.selectedType || "";
  const nextIsNew = nextType === "New";
  const prevIsNew = prevType === "New";

  const previousSendContactId = state.data.estimateSendContactId;
  const data = resetFields(state.data, TYPE_DEPENDENT_FIELDS);
  // サービス選択後の初回操作選択（"" → Change 等）は契約ポインタを残す
  if (
    !prevIsNew &&
    prevType === "" &&
    CONTINUATION_OPS.has(nextType) &&
    state.data.contractServiceId
  ) {
    data.contractServiceId = state.data.contractServiceId;
    data.contractServiceName = state.data.contractServiceName;
    data.serviceLifecycle = state.data.serviceLifecycle;
    data.contractHistoryId = state.data.contractHistoryId;
    data.autoHistoryName = state.data.autoHistoryName;
    data.baseHistoryVersion = state.data.baseHistoryVersion;
    data.nextHistoryVersion = state.data.nextHistoryVersion;
    data.billingAccountId = state.data.billingAccountId;
    data.renewEligible = state.data.renewEligible;
    data.estimateSendContactId = previousSendContactId;
    data.contractHistoryName =
      nextType === "Cancel"
        ? buildCancelHistoryName(data.autoHistoryName)
        : state.data.contractHistoryName;
  }
  data.selectedType = nextType;
  if (nextIsNew && (data.taxPercent == null || data.taxPercent === "")) {
    data.taxPercent = 10;
  }
  if (nextIsNew) {
    data.estimateSendContactId =
      data.opportunityContactId || data.estimateSendContactId || "";
  }
  if (!nextIsNew && nextType !== "") {
    data.entryMode = "continuation";
  } else if (nextIsNew) {
    data.entryMode = "new";
  }
  return {
    ...state,
    data,
    ui: { step2Mounted: true, step3Mounted: false },
    async: { ...state.async, loadingStep3: false }
  };
}

function reduceMergeStep2(state, action) {
  const fields = action.fields || {};
  const serviceChanged =
    Object.prototype.hasOwnProperty.call(fields, "contractServiceId") &&
    fields.contractServiceId !== state.data.contractServiceId;
  const historyChanged =
    Object.prototype.hasOwnProperty.call(fields, "contractHistoryId") &&
    fields.contractHistoryId !== state.data.contractHistoryId;

  if (!serviceChanged && !historyChanged) {
    return { ...state, data: { ...state.data, ...fields } };
  }

  const merged = resetFields(
    { ...state.data, ...fields },
    CONTRACT_DEPENDENT_FIELDS
  );
  // 契約サービス・契約履歴のどちらが変わっても、追加項目は旧契約由来なので捨てる。
  merged.contractServiceCustomFields =
    serviceChanged || historyChanged
      ? {}
      : { ...(fields.contractServiceCustomFields || {}) };
  return { ...state, data: merged };
}

/**
 * Step3 の許可フィールドだけを取り込む。
 * endDate は contractEndDate へ正規化する（両方来た場合は contractEndDate を優先）。
 */
function reduceMergeStep3(state, action) {
  const fields = action.fields || {};
  const next = { ...state.data };
  let changed = false;

  STEP3_ALLOWED_FIELDS.forEach((key) => {
    if (!Object.prototype.hasOwnProperty.call(fields, key)) {
      return;
    }
    if (key === "endDate") {
      // contractEndDate が明示されている場合はエイリアスを無視する。
      if (Object.prototype.hasOwnProperty.call(fields, "contractEndDate")) {
        return;
      }
      if (next.contractEndDate !== fields.endDate) {
        next.contractEndDate = fields.endDate;
        changed = true;
      }
      return;
    }
    if (next[key] !== fields[key]) {
      next[key] = fields[key];
      changed = true;
    }
  });

  return changed ? { ...state, data: next } : state;
}

/**
 * 契約サービスを切り替えた時点で、旧契約に由来する入力を即座に破棄する。
 * Apex の応答を待たないので「画面はB・内部はA」の状態が生じない。
 */
function reduceSelectContractServiceStart(state, action) {
  const contractServiceId = action.contractServiceId || "";
  const data = resetFields(state.data, CONTRACT_DEPENDENT_FIELDS);
  data.contractServiceId = contractServiceId;
  // Change／Renew／Cancel はサービス名テキスト入力がないため、選択ラベルをヘッダ／状態へ載せる
  data.contractServiceName = contractServiceId
    ? (action.contractServiceName || "").trim()
    : "";
  data.serviceLifecycle = contractServiceId
    ? action.serviceLifecycle || ""
    : "";
  data.contractHistoryId = "";
  data.autoHistoryName = "";
  // 履歴名は基本情報のみで編集。サービス切替時は旧契約由来なので捨てる。
  data.contractHistoryName = "";
  data.baseHistoryVersion = null;
  data.nextHistoryVersion = null;
  data.renewEligible = null;
  data.contractServiceCustomFields = {};
  // 追加項目パネルはデフォルト開く
  data.serviceCustomFieldsExpanded = true;
  data.historyCustomFieldsExpanded = true;
  // Lifecycle に合わない操作を補正（続きで操作未選択 "" の Spot は Change）
  const lifecycle = data.serviceLifecycle;
  const type = data.selectedType;
  if (!lifecycle) {
    data.selectedType = "";
  } else if (lifecycle === "Spot" && type !== "Change") {
    data.selectedType = "Change";
  } else if (lifecycle === "Term" && type !== "" && !CONTINUATION_OPS.has(type)) {
    data.selectedType = "";
  }
  return {
    ...state,
    data,
    async: {
      ...state.async,
      serviceRequestId: state.async.serviceRequestId + 1,
      loadingContractHistory: Boolean(contractServiceId)
    }
  };
}

function reduceSelectContractServiceResult(state, action, result) {
  // 連番が一致しない＝より新しい選択が行われた後の応答なので採用しない。
  if (action.requestId !== state.async.serviceRequestId) {
    return state;
  }
  const data = { ...state.data };
  data.contractHistoryId = (result && result.historyId) || "";
  data.autoHistoryName = (result && result.historyName) || "";
  data.baseHistoryVersion =
    result && result.version != null ? result.version : null;
  data.nextHistoryVersion =
    result && result.nextVersion != null ? result.nextVersion : null;
  data.renewEligible = result ? result.renewEligible === true : null;
  if (data.selectedType === "Cancel") {
    data.contractHistoryName = buildCancelHistoryName(data.autoHistoryName);
  }
  data.estimateSendContactId =
    (result && result.estimateSendContactId) || "";
  return {
    ...state,
    data,
    async: { ...state.async, loadingContractHistory: false }
  };
}

/**
 * New では常にベースVersionを持たず、作成Versionは 1 に固定される。
 * この不変条件を1か所で保証し、各コンポーネントでの再現を不要にする。
 */
function normalizeDerivedFields(state) {
  const data = state.data;
  if (data.selectedType !== "New") {
    return state;
  }
  if (
    data.baseHistoryVersion === null &&
    data.nextHistoryVersion === 1 &&
    data.renewEligible === null
  ) {
    return state;
  }
  return {
    ...state,
    data: {
      ...data,
      baseHistoryVersion: null,
      nextHistoryVersion: 1,
      renewEligible: null
    }
  };
}

function reducePresetSuccess(state, action) {
  return {
    ...state,
    step: 1,
    data: buildWizardDataFromPreset(action.preset),
    ui: { step2Mounted: true, step3Mounted: false },
    async: {
      ...state.async,
      loadingPreset: false,
      presetError: "",
      loadedPresetKey: action.key || "",
      failedPresetKey: ""
    }
  };
}

function reducePresetFailure(state, action) {
  return {
    ...createInitialWizardState(),
    async: {
      ...createInitialWizardState().async,
      presetError: action.message || "",
      failedPresetKey: action.key || ""
    }
  };
}

export function reduceWizardState(state, action) {
  const next = applyAction(state, action);
  return next === state ? state : normalizeDerivedFields(next);
}

function applyAction(state, action) {
  if (!action || !action.type) {
    return state;
  }

  switch (action.type) {
    case WIZARD_ACTIONS.INITIALIZE_NEW:
      return createInitialWizardState();

    case WIZARD_ACTIONS.PRESET_LOAD_START:
      return {
        ...state,
        async: {
          ...state.async,
          loadingPreset: true,
          presetError: ""
        }
      };

    case WIZARD_ACTIONS.PRESET_LOAD_SUCCESS:
      return reducePresetSuccess(state, action);

    case WIZARD_ACTIONS.PRESET_LOAD_FAILURE:
      return reducePresetFailure(state, action);

    case WIZARD_ACTIONS.PRESET_CLEAR_FAILURE:
      return {
        ...state,
        async: {
          ...state.async,
          presetError: "",
          failedPresetKey: ""
        }
      };

    case WIZARD_ACTIONS.SET_OPPORTUNITY: {
      const opportunityName = action.opportunityName || "";
      const accountName = action.accountName || "";
      const opportunityContactId = action.opportunityContactId || "";
      // 取得失敗や未解決の空値でプリセット由来の名前を消さない。
      if (!opportunityName && !accountName && !opportunityContactId) {
        return state;
      }
      if (
        opportunityName === state.data.opportunityName &&
        accountName === state.data.accountName &&
        opportunityContactId === (state.data.opportunityContactId || "")
      ) {
        return state;
      }
      const next = {
        ...state.data,
        opportunityName: opportunityName || state.data.opportunityName,
        accountName: accountName || state.data.accountName,
        opportunityContactId:
          opportunityContactId || state.data.opportunityContactId || ""
      };
      if (
        next.selectedType === "New" &&
        !next.estimateSendContactId &&
        next.opportunityContactId
      ) {
        next.estimateSendContactId = next.opportunityContactId;
      }
      return {
        ...state,
        data: next
      };
    }

    case WIZARD_ACTIONS.SET_TYPE:
      return reduceSetType(state, action);

    case WIZARD_ACTIONS.SET_ENTRY_MODE: {
      const entryMode =
        action.entryMode === "continuation" ? "continuation" : "new";
      if (entryMode === state.data.entryMode) {
        return state;
      }
      if (entryMode === "new") {
        return reduceSetType(
          {
            ...state,
            data: { ...state.data, entryMode, serviceLifecycle: "" }
          },
          { type: WIZARD_ACTIONS.SET_TYPE, selectedType: "New" }
        );
      }
      // 続き: 操作未選択にし、契約依存をクリア
      const data = resetFields(
        { ...state.data, entryMode, serviceLifecycle: "" },
        TYPE_DEPENDENT_FIELDS
      );
      data.entryMode = "continuation";
      data.selectedType = "";
      data.serviceLifecycle = "";
      return {
        ...state,
        data,
        ui: { step2Mounted: true, step3Mounted: false },
        async: { ...state.async, loadingStep3: false }
      };
    }

    case WIZARD_ACTIONS.SET_STEP: {
      const step = Number(action.step);
      if (!step || step < 1 || step > 2) {
        return state;
      }
      return { ...state, step, ui: withMountedSteps(state.ui, step) };
    }

    case WIZARD_ACTIONS.MERGE_STEP2:
      return reduceMergeStep2(state, action);

    case WIZARD_ACTIONS.MERGE_STEP3:
      return reduceMergeStep3(state, action);

    case WIZARD_ACTIONS.SET_STEP3_LOADING: {
      const loading = action.loading === true;
      if (loading === state.async.loadingStep3) {
        return state;
      }
      return { ...state, async: { ...state.async, loadingStep3: loading } };
    }

    case WIZARD_ACTIONS.SELECT_CONTRACT_SERVICE_START:
      return reduceSelectContractServiceStart(state, action);

    case WIZARD_ACTIONS.SELECT_CONTRACT_SERVICE_SUCCESS:
      return reduceSelectContractServiceResult(state, action, action.result);

    case WIZARD_ACTIONS.SELECT_CONTRACT_SERVICE_FAILURE:
      return reduceSelectContractServiceResult(state, action, null);

    case WIZARD_ACTIONS.SAVE_START:
      return { ...state, async: { ...state.async, saving: true } };

    case WIZARD_ACTIONS.SAVE_END:
      return { ...state, async: { ...state.async, saving: false } };

    default:
      return state;
  }
}

/** 次へ / 保存に進めるか。非同期処理中は常に false。 */
export function canLeaveCurrentStep(state) {
  return (
    !state.async.loadingPreset &&
    !state.async.loadingContractHistory &&
    !state.async.loadingStep3 &&
    !state.async.saving &&
    !state.async.loadingDocumentDefaults
  );
}

let rowIdSequence = 0;

/**
 * 商品明細行の一意な ID を発行する。
 *
 * 以前は各コンポーネントが持つ連番から `row-N` を組み立てていたため、
 * 途中の行を削除した明細を読み直すと既存 ID と衝突することがあった。
 * 発行元を1か所にし、既存 ID とは決して重ならない形式にする。
 */
export function createRowId() {
  rowIdSequence += 1;
  return `row-${Date.now().toString(36)}-${rowIdSequence}`;
}

/** Version 表示用。有限な数値だけ文字列化し、それ以外は空文字。 */
export function formatHistoryVersion(value) {
  if (value == null || value === "") {
    return "";
  }
  const numeric = Number(value);
  return Number.isFinite(numeric) ? String(numeric) : "";
}

/** 同じプリセットを再読込すべきか（成功済み・失敗済みは再試行しない）。 */
// 仕様: Core 第4.10節、第11.9節、日付仕様 第2.6節
export function applyEstimateDocumentDefaults(state, defaults) {
  if (!state || !defaults) {
    return state;
  }
  const mode = defaults.estimateSendMode;
  const data = { ...state.data };
  data.defaultMonthlyCycles = defaults.defaultMonthlyCycles;
  data.estimateValidMonths = defaults.estimateValidMonths;
  data.estimateSendMode = mode;
  data.taxRoundingMode = defaults.taxRoundingMode;
  data.quantityUnitPriceRoundingMode =
    defaults.quantityUnitPriceRoundingMode;
  data.amountRoundingMode = defaults.amountRoundingMode;
  // 仕様: Core 第4.6節、第11.9節。明細金額計算へ OrgDefault を載せる。
  setAmountCalculationRoundingModes({
    quantityUnitPriceRoundingMode: defaults.quantityUnitPriceRoundingMode,
    amountRoundingMode: defaults.amountRoundingMode
  });
  if (mode === "Unused") {
    return { ...state, data };
  }
  if (!data.estimateDate) {
    data.estimateDate = defaults.today || "";
  }
  if (!data.estimateValidDateTouched) {
    data.estimateValidDate = addCalendarMonths(
      data.estimateDate,
      defaults.estimateValidMonths
    );
  }
  return { ...state, data };
}

export function followEstimateValidDate(estimateDate, months, touched, currentValid) {
  if (touched) {
    return currentValid || "";
  }
  return addCalendarMonths(estimateDate, months);
}

function addCalendarMonths(isoDate, months) {
  if (!isoDate || !Number.isInteger(months)) {
    return "";
  }
  const parts = String(isoDate).split("-").map(Number);
  if (parts.length < 3 || parts.some((n) => !Number.isFinite(n))) {
    return "";
  }
  const year = parts[0];
  const monthIndex = parts[1] - 1 + months;
  const nextYear = year + Math.floor(monthIndex / 12);
  const nextMonth = ((monthIndex % 12) + 12) % 12;
  const lastDay = new Date(Date.UTC(nextYear, nextMonth + 1, 0)).getUTCDate();
  const day = Math.min(parts[2], lastDay);
  return `${nextYear}-${String(nextMonth + 1).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
}

export function buildCancelHistoryName(baseName) {
  const base = (baseName || "").trim();
  if (!base) {
    return "";
  }
  return base.endsWith("解約") ? base : `${base} 解約`;
}

export function shouldLoadPreset(state, key) {
  if (!key) {
    return false;
  }
  if (state.async.loadingPreset) {
    return false;
  }
  if (state.async.loadedPresetKey === key) {
    return false;
  }
  if (state.async.failedPresetKey === key) {
    return false;
  }
  return true;
}
