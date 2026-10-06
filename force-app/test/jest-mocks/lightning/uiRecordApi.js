const {
  createLdsTestWireAdapter
} = require("@salesforce/wire-service-jest-util");

const getRecord = createLdsTestWireAdapter(jest.fn());
const getRecords = createLdsTestWireAdapter(jest.fn());
const getRecordCreateDefaults = createLdsTestWireAdapter(jest.fn());
const getRecordUi = createLdsTestWireAdapter(jest.fn());
const getRecordNotifyChange = jest.fn();

function fieldApiNameOf(field) {
  if (!field) {
    return "";
  }
  if (typeof field === "string") {
    return field;
  }
  if (typeof field.fieldApiName === "string") {
    return field.objectApiName
      ? field.objectApiName + "." + field.fieldApiName
      : field.fieldApiName;
  }
  return "";
}

const getFieldValue = jest.fn((record, field) => {
  const qualified = fieldApiNameOf(field);
  if (!qualified) {
    return undefined;
  }
  const shortName = qualified.includes(".")
    ? qualified.slice(qualified.indexOf(".") + 1)
    : qualified;
  const parts = shortName.split(".");
  let current = record;
  while (parts.length > 0 && current && current.fields) {
    const part = parts.shift();
    const stored = current.fields[part];
    if (stored === undefined) {
      return undefined;
    }
    current = stored.value;
  }
  return current;
});

module.exports = {
  getRecord,
  getRecords,
  getRecordCreateDefaults,
  getRecordUi,
  getRecordNotifyChange,
  getFieldValue,
  updateRecord: jest.fn().mockResolvedValue({}),
  createRecord: jest.fn().mockResolvedValue({}),
  deleteRecord: jest.fn().mockResolvedValue(),
  generateRecordInputForCreate: jest.fn(),
  generateRecordInputForUpdate: jest.fn(),
  createRecordInputFilteredByEditedFields: jest.fn(),
  getRecordInput: jest.fn(),
  refresh: jest.fn().mockResolvedValue(),
  notifyRecordUpdateAvailable: jest.fn().mockResolvedValue()
};
