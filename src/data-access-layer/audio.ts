import { invoke } from '@tauri-apps/api/core';
import { AppListSchema, InputDeviceListSchema } from '../schemas/audio';

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
