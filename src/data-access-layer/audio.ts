import { invoke } from '@tauri-apps/api/core';
import {
  AppListSchema,
  InputDeviceListSchema,
  RecordingListSchema,
  RecordingPathSchema,
  DataUrlSchema,
} from '../schemas/audio.ts';

export const getApplications = async () => {
  const applications = await invoke('list_apps');
  return AppListSchema.parse(applications);
};

export const getInputDevices = async () => {
  const inputDevices = await invoke('list_input_devices');
  return InputDeviceListSchema.parse(inputDevices);
};

export const startCapture = async (id: string) => {
  await invoke('start_capture', { id });
};

export const stopCapture = async () => {
  await invoke('stop_capture');
};

export const getRecordings = async () => {
  const recordings = await invoke('list_recordings');
  return RecordingListSchema.parse(recordings);
};

export const getRecordingDataUrl = async (path: string) => {
  const safePath = RecordingPathSchema.parse(path);
  const url = await invoke('get_recording_data_url', { path: safePath });
  return DataUrlSchema.parse(url);
};

export const deleteRecording = async (path: string) => {
  const safePath = RecordingPathSchema.parse(path);
  await invoke('delete_recording', { path: safePath });
};
