import { useId } from 'react'
import { CUSTOM_ID, type DurationChoice, type DurationPreset } from '@/lib/createRetainer'

interface DurationFieldProps {
  legend: string
  hint: string
  presets: readonly DurationPreset[]
  value: DurationChoice
  onChange: (next: DurationChoice) => void
  onBlur: () => void
  error: string | null
}

/** Preset options as a radio group, plus "Custom" with a number of hours. */
export function DurationField({ legend, hint, presets, value, onChange, onBlur, error }: DurationFieldProps) {
  const uid = useId()
  const hoursId = `${uid}-hours`
  const errorId = `${uid}-error`
  const hintId = `${uid}-hint`
  const custom = value.id === CUSTOM_ID

  return (
    <fieldset className="min-w-0 border-0 p-0" aria-describedby={error ? `${hintId} ${errorId}` : hintId}>
      <legend className="p-0 font-bold">{legend}</legend>
      <p id={hintId} className="mb-2 mt-1 text-step--1 text-muted">
        {hint}
      </p>
      <div className="flex flex-wrap gap-2">
        {presets.map((preset) => (
          <label key={preset.id} className="choice">
            <input
              type="radio"
              name={uid}
              value={preset.id}
              checked={value.id === preset.id}
              onChange={() => onChange({ ...value, id: preset.id })}
            />
            <span>{preset.label}</span>
          </label>
        ))}
        <label className="choice">
          <input
            type="radio"
            name={uid}
            value={CUSTOM_ID}
            checked={custom}
            onChange={() => onChange({ ...value, id: CUSTOM_ID })}
          />
          <span>Custom</span>
        </label>
      </div>
      {custom && (
        <div className="mt-3 flex items-center gap-2">
          <input
            id={hoursId}
            className="field num max-w-[9rem]"
            inputMode="decimal"
            enterKeyHint="done"
            autoComplete="off"
            autoCapitalize="none"
            autoCorrect="off"
            spellCheck={false}
            aria-label={`${legend}, in hours`}
            aria-invalid={error !== null}
            value={value.customHours}
            onChange={(event) => onChange({ ...value, customHours: event.target.value })}
            onBlur={onBlur}
          />
          <span className="text-muted">hours</span>
        </div>
      )}
      {error && (
        <p id={errorId} className="mt-2 text-step--1 text-objected">
          {error}
        </p>
      )}
    </fieldset>
  )
}
