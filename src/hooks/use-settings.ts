import { useMemo } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { loadSettings, saveSettings, updateSettings } from '../data-access-layer/settings.ts';
import { settingsSchema, type AppSettings } from '../schemas/settings.ts';

const QUERY_KEY = ['settings'] as const;

export function useSettings() {
  const queryClient = useQueryClient();

  const query = useQuery({
    queryKey: QUERY_KEY,
    queryFn: async () => loadSettings(),
    staleTime: Infinity,
    gcTime: Infinity,
    refetchOnWindowFocus: false,
  });

  const setMutation = useMutation({
    mutationFn: async (next: AppSettings) => {
      const parsed = settingsSchema.parse(next);
      saveSettings(parsed);
      return parsed;
    },
    onSuccess: (data) => {
      queryClient.setQueryData(QUERY_KEY, data);
    },
  });

  const updateMutation = useMutation({
    mutationFn: async (partial: Partial<AppSettings>) => updateSettings(partial),
    onSuccess: (data) => {
      queryClient.setQueryData(QUERY_KEY, data);
    },
  });

  return useMemo(
    () => ({
      data: query.data,
      isLoading: query.isLoading,
      error: query.error,
      set: (next: AppSettings) => setMutation.mutate(next),
      update: (partial: Partial<AppSettings>) => updateMutation.mutate(partial),
      isSaving: setMutation.isPending || updateMutation.isPending,
    }),
    [query.data, query.isLoading, query.error, setMutation, updateMutation],
  );
}

export type UseSettingsReturn = ReturnType<typeof useSettings>;
