import { useEffect } from 'react';
import { useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { useSettings } from '../../hooks/use-settings.ts';
import { settingsSchema } from '../../schemas/settings.ts';

const formSchema = settingsSchema.pick({ geminiApiKey: true });

type SettingsFormValues = z.infer<typeof formSchema>;

export function SettingsPage() {
  const { data, isLoading, isSaving, update } = useSettings();
  const {
    register,
    handleSubmit,
    reset,
    formState: { errors, isSubmitting, isDirty },
  } = useForm<SettingsFormValues>({
    resolver: zodResolver(formSchema),
    defaultValues: { geminiApiKey: '' },
    mode: 'onChange',
  });

  useEffect(() => {
    if (data) {
      reset({ geminiApiKey: data.geminiApiKey ?? '' });
    }
  }, [data, reset]);

  const onSubmit = (values: SettingsFormValues) => {
    update({ geminiApiKey: values.geminiApiKey });
  };

  return (
    <div className="p-4">
      <h3 className="mb-4 text-lg font-semibold">Settings</h3>
      <form className="max-w-lg space-y-4" onSubmit={handleSubmit(onSubmit)}>
        <div className="space-y-2">
          <label htmlFor="geminiApiKey" className="text-sm font-medium">
            Gemini API Key
          </label>
          <input
            id="geminiApiKey"
            type="password"
            placeholder="Paste your Gemini API key"
            className="w-full rounded border px-3 py-2 text-sm"
            autoComplete="off"
            disabled={isLoading}
            {...register('geminiApiKey')}
          />
          {errors.geminiApiKey && <div className="text-xs text-red-600">{errors.geminiApiKey.message}</div>}
        </div>
        <div className="flex items-center gap-2">
          <button
            type="submit"
            className="rounded border px-3 py-2 text-sm disabled:opacity-50"
            disabled={isSubmitting || isSaving || !isDirty}
          >
            Save
          </button>
        </div>
      </form>
    </div>
  );
}

export default SettingsPage;
