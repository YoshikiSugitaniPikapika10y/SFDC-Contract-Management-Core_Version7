const mockGetRecordNotifyChange = jest.fn();
const mockNavigateToContractHistoryRecord = jest.fn();

jest.mock(
  "lightning/actions",
  () => ({
    CloseActionScreenEvent: class CloseActionScreenEvent extends Event {
      constructor() {
        super("closeActionScreen");
      }
    }
  }),
  { virtual: true }
);

jest.mock(
  "lightning/refresh",
  () => ({
    RefreshEvent: class RefreshEvent extends Event {
      constructor() {
        super("refresh");
      }
    }
  }),
  { virtual: true }
);

jest.mock(
  "lightning/uiRecordApi",
  () => ({
    getRecordNotifyChange: (...args) => mockGetRecordNotifyChange(...args)
  }),
  { virtual: true }
);

jest.mock(
  "c/orderWizardNavigation",
  () => ({
    navigateToContractHistoryRecord: (...args) =>
      mockNavigateToContractHistoryRecord(...args)
  }),
  { virtual: true }
);

import { CloseActionScreenEvent } from "lightning/actions";
import { RefreshEvent } from "lightning/refresh";
import {
  HISTORY_STATUS_ARCHIVE,
  closeOrderRecordAction,
  closeOrderWizard,
  ensureRecordActionDataLoad,
  handleMissingRecordActionId,
  handleOrderModalRequestClose,
  isOrderActionBootstrapping,
  markOrderRecordForRefresh,
  notifyOrderRecordStatusChanged,
  refreshOnRecordActionUnmount,
  refreshOrderRecordPage,
  requestOrderWizardClose,
  resetRecordActionLoadState,
  scheduleOrderRecordPageRefresh,
  scheduleRecordActionLoad
} from "c/orderWizardClose";

async function flushPromises() {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
}

describe("orderWizardClose", () => {
  beforeEach(() => {
    jest.useFakeTimers();
    mockGetRecordNotifyChange.mockReset();
    mockNavigateToContractHistoryRecord.mockReset();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  test("Archive状態定数を業務値のまま公開する", () => {
    expect(HISTORY_STATUS_ARCHIVE).toBe("Archive");
  });

  test("レコード更新を即時通知し、RefreshEventと遅延再通知を行う", () => {
    const component = { dispatchEvent: jest.fn() };

    refreshOrderRecordPage(component, "a01AAA");
    expect(mockGetRecordNotifyChange).toHaveBeenCalledWith([
      { recordId: "a01AAA" }
    ]);
    expect(component.dispatchEvent).toHaveBeenCalledWith(
      expect.any(RefreshEvent)
    );

    jest.advanceTimersByTime(299);
    expect(mockGetRecordNotifyChange).toHaveBeenCalledTimes(1);
    jest.advanceTimersByTime(1);
    expect(mockGetRecordNotifyChange).toHaveBeenCalledTimes(2);

    refreshOrderRecordPage(component, null);
    scheduleOrderRecordPageRefresh(null);
    expect(mockGetRecordNotifyChange).toHaveBeenCalledTimes(2);
  });

  test("通常閉じるは指定IDを優先して更新後にQuick Actionを閉じる", () => {
    const component = {
      recordId: "a01HOST",
      dispatchEvent: jest.fn()
    };

    closeOrderWizard(component, { recordId: "a01ARG" });

    expect(mockGetRecordNotifyChange).toHaveBeenCalledWith([
      { recordId: "a01ARG" }
    ]);
    expect(component.dispatchEvent).toHaveBeenCalledWith(
      expect.any(RefreshEvent)
    );
    expect(component.dispatchEvent).toHaveBeenCalledWith(
      expect.any(CloseActionScreenEvent)
    );
  });

  test("更新不要とID無し更新を区別して閉じる", () => {
    const withoutRefresh = { recordId: "a01AAA", dispatchEvent: jest.fn() };
    closeOrderWizard(withoutRefresh, { refresh: false });
    expect(mockGetRecordNotifyChange).not.toHaveBeenCalled();
    expect(
      withoutRefresh.dispatchEvent.mock.calls.some(
        ([event]) => event instanceof RefreshEvent
      )
    ).toBe(false);

    const withoutId = { dispatchEvent: jest.fn() };
    closeOrderWizard(withoutId);
    expect(withoutId.dispatchEvent).toHaveBeenCalledWith(
      expect.any(RefreshEvent)
    );
    expect(withoutId.dispatchEvent).toHaveBeenCalledWith(
      expect.any(CloseActionScreenEvent)
    );
  });

  test("子ウィザードから親へ閉じる条件とIDを伝播する", () => {
    const component = {
      recordId: "a01HOST",
      dispatchEvent: jest.fn()
    };

    requestOrderWizardClose(component, {
      refresh: false,
      recordId: "a01ARG"
    });

    const event = component.dispatchEvent.mock.calls[0][0];
    expect(event.type).toBe("requestclose");
    expect(event.bubbles).toBe(true);
    expect(event.composed).toBe(true);
    expect(event.detail).toEqual({ refresh: false, recordId: "a01ARG" });
  });

  test("親モーダルは更新指定時だけレコードを更新して閉じる", () => {
    const modal = {
      recordId: "a01HOST",
      dispatchEvent: jest.fn(),
      close: jest.fn()
    };

    handleOrderModalRequestClose(modal, {
      detail: { recordId: "a01ARG" }
    });
    expect(mockGetRecordNotifyChange).toHaveBeenCalledWith([
      { recordId: "a01ARG" }
    ]);
    expect(modal.close).toHaveBeenCalledTimes(1);

    mockGetRecordNotifyChange.mockClear();
    handleOrderModalRequestClose(modal, {
      detail: { refresh: false }
    });
    expect(mockGetRecordNotifyChange).not.toHaveBeenCalled();
    expect(modal.close).toHaveBeenCalledTimes(2);
  });

  test.each([
    [{ isLoading: true, recordId: "a01", _recordActionMissingHandled: false }, true],
    [{ isLoading: false, recordId: null, _recordActionMissingHandled: false }, true],
    [{ isLoading: false, recordId: null, _recordActionMissingHandled: true }, false],
    [{ isLoading: false, recordId: "a01", _recordActionMissingHandled: false }, false]
  ])("起動中状態をロードとID確定状況から判定する", (component, expected) => {
    expect(isOrderActionBootstrapping(component)).toBe(expected);
  });

  test("受注状態変更イベントは引数IDを優先する", () => {
    const component = {
      recordId: "a01HOST",
      dispatchEvent: jest.fn()
    };

    notifyOrderRecordStatusChanged(component, "a01ARG");
    const event = component.dispatchEvent.mock.calls[0][0];
    expect(event.type).toBe("orderrecordstatuschanged");
    expect(event.detail).toEqual({ recordId: "a01ARG" });
    expect(event.bubbles).toBe(true);
    expect(event.composed).toBe(true);
  });

  test("アンマウント時は保留IDだけ更新して契約履歴詳細へ戻す", () => {
    const host = {
      recordId: "a01HOST",
      dispatchEvent: jest.fn()
    };

    refreshOnRecordActionUnmount(host);
    expect(mockGetRecordNotifyChange).not.toHaveBeenCalled();

    markOrderRecordForRefresh(host, "a01ARG");
    refreshOnRecordActionUnmount(host);
    expect(mockGetRecordNotifyChange).toHaveBeenCalledWith([
      { recordId: "a01ARG" }
    ]);
    expect(host.dispatchEvent).toHaveBeenCalledWith(expect.any(RefreshEvent));
    expect(mockNavigateToContractHistoryRecord).toHaveBeenCalledWith(
      host,
      "a01ARG"
    );
  });

  test("レコードアクション閉じるは更新条件を維持して詳細へ戻す", () => {
    const host = {
      recordId: "a01HOST",
      dispatchEvent: jest.fn()
    };

    closeOrderRecordAction(host, { refresh: false, recordId: "a01ARG" });
    expect(mockGetRecordNotifyChange).not.toHaveBeenCalled();
    expect(host.dispatchEvent).toHaveBeenCalledWith(
      expect.any(CloseActionScreenEvent)
    );
    expect(mockNavigateToContractHistoryRecord).toHaveBeenCalledWith(
      host,
      "a01ARG"
    );
  });

  test("ロード状態を接続ごとに初期化し、同じIDの重複ロードを止める", () => {
    const loadFn = jest.fn();
    const component = {
      recordId: "a01AAA",
      _loadedOrderActionRecordId: "old",
      _recordActionMissingHandled: true,
      _recordActionLoadScheduled: true
    };

    resetRecordActionLoadState(component);
    expect(component).toEqual(
      expect.objectContaining({
        _loadedOrderActionRecordId: null,
        _recordActionMissingHandled: false,
        _recordActionLoadScheduled: false
      })
    );
    expect(ensureRecordActionDataLoad(component, loadFn)).toBe(true);
    expect(loadFn).toHaveBeenCalledTimes(1);
    expect(ensureRecordActionDataLoad(component, loadFn)).toBe(false);
    expect(loadFn).toHaveBeenCalledTimes(1);
  });

  test("ID未指定は一度だけエラー化し、対応済みまたはロード済みなら触らない", () => {
    const component = {
      recordId: null,
      _loadedOrderActionRecordId: null,
      _recordActionMissingHandled: false,
      isLoading: true,
      errorMessage: ""
    };

    handleMissingRecordActionId(component);
    expect(component.isLoading).toBe(false);
    expect(component.errorMessage).toBe("契約履歴IDが指定されていません。");
    expect(component._recordActionMissingHandled).toBe(true);

    component.errorMessage = "維持";
    handleMissingRecordActionId(component);
    expect(component.errorMessage).toBe("維持");

    const withoutErrorProperty = {
      recordId: null,
      _loadedOrderActionRecordId: null,
      _recordActionMissingHandled: false,
      isLoading: true
    };
    handleMissingRecordActionId(withoutErrorProperty);
    expect(Object.prototype.hasOwnProperty.call(withoutErrorProperty, "errorMessage")).toBe(
      false
    );
  });

  test("遅れて入るrecordIdをマイクロタスクで一度だけロードする", async () => {
    const loadFn = jest.fn();
    const component = {
      recordId: null,
      _loadedOrderActionRecordId: null,
      _recordActionMissingHandled: false,
      _recordActionLoadScheduled: false,
      isLoading: true,
      errorMessage: ""
    };

    scheduleRecordActionLoad(component, loadFn);
    scheduleRecordActionLoad(component, loadFn);
    expect(component._recordActionLoadScheduled).toBe(true);

    component.recordId = "a01LATE";
    await flushPromises();

    expect(loadFn).toHaveBeenCalledTimes(1);
    expect(component._loadedOrderActionRecordId).toBe("a01LATE");
    expect(component._recordActionLoadScheduled).toBe(false);
    expect(component.errorMessage).toBe("");
  });

  test("マイクロタスク後もIDが無ければ不足エラーへ確定する", async () => {
    const component = {
      recordId: null,
      _loadedOrderActionRecordId: null,
      _recordActionMissingHandled: false,
      _recordActionLoadScheduled: false,
      isLoading: true,
      errorMessage: ""
    };

    scheduleRecordActionLoad(component, jest.fn());
    await flushPromises();

    expect(component._recordActionLoadScheduled).toBe(false);
    expect(component._recordActionMissingHandled).toBe(true);
    expect(component.errorMessage).toBe("契約履歴IDが指定されていません。");
  });
});
