/**
 * 共有ルール／FLS を bypass して DML する入口（SYSTEM_MODE）。
 * 見積保存・請求生成など、実行ユーザ権限に依存させないサーバ処理から利用する。
 */
public without sharing class SystemContextAccess {
    public static Database.SaveResult[] insertRecords(List<SObject> records) {
        return insertRecords(records, true);
    }

    public static Database.SaveResult[] insertRecords(
        List<SObject> records,
        Boolean allOrNone
    ) {
        if (records == null || records.isEmpty()) {
            return new List<Database.SaveResult>();
        }
        return Database.insert(records, allOrNone, AccessLevel.SYSTEM_MODE);
    }

    public static Database.SaveResult[] updateRecords(List<SObject> records) {
        return updateRecords(records, true);
    }

    public static Database.SaveResult[] updateRecords(
        List<SObject> records,
        Boolean allOrNone
    ) {
        if (records == null || records.isEmpty()) {
            return new List<Database.SaveResult>();
        }
        return Database.update(records, allOrNone, AccessLevel.SYSTEM_MODE);
    }

    public static Database.DeleteResult[] deleteRecords(List<SObject> records) {
        return deleteRecords(records, true);
    }

    public static Database.DeleteResult[] deleteRecords(
        List<SObject> records,
        Boolean allOrNone
    ) {
        if (records == null || records.isEmpty()) {
            return new List<Database.DeleteResult>();
        }
        return Database.delete(records, allOrNone, AccessLevel.SYSTEM_MODE);
    }

    public static Database.UpsertResult[] upsertRecords(List<SObject> records) {
        return upsertRecords(records, true);
    }

    public static Database.UpsertResult[] upsertRecords(
        List<SObject> records,
        Boolean allOrNone
    ) {
        if (records == null || records.isEmpty()) {
            return new List<Database.UpsertResult>();
        }
        return Database.upsert(records, allOrNone, AccessLevel.SYSTEM_MODE);
    }
}