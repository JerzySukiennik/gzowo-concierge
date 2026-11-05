// Gzowo Concierge - timer tools: start, list and cancel countdowns that show on the Mac island and ring in the room and on the phone.
import { startTimer, cancelTimer, listTimers } from '../timers.mjs';

const ROOM = 'pokoj';

export const timerTools = [
  {
    name: 'timer_start',
    action: 'timer.set',
    policy: 'auto',
    description: "Start a countdown timer (\"ustaw timer na 10 minut\", \"minutnik na pizzę 12 min\"). It shows live on the Mac island and rings on the Mac, on his phone and, if he asked in his room, on the room speaker. For a clock time (\"obudź mnie o 7\") use the calendar with an alarm instead. Give the length in seconds.",
    parameters: { type: 'object', properties: {
      seconds: { type: 'number', description: 'Length in seconds, for example 600 for 10 minutes' },
      label: { type: 'string', description: 'Short name in Polish if he gave one (pizza, pranie, przerwa), otherwise empty' },
    }, required: ['seconds'] },
    summarize: a => `Ustawiam timer${a.label ? ` „${a.label}”` : ''}`,
    run: ({ seconds, label }, ctx = {}) => startTimer({ seconds, label, origin: ctx.thread === ROOM ? 'room' : 'chat' }),
  },
  {
    name: 'timer_list',
    action: 'timer.list',
    policy: 'auto',
    description: 'List running timers with the time left. Use when he asks how much time is left.',
    parameters: { type: 'object', properties: {} },
    summarize: () => 'Sprawdzam timery',
    run: () => ({ timers: listTimers() }),
  },
  {
    name: 'timer_cancel',
    action: 'timer.cancel',
    policy: 'auto',
    description: 'Cancel a running timer by its label, or all timers when he says so. If the result lists several, ask which one.',
    parameters: { type: 'object', properties: {
      label: { type: 'string', description: 'Label of the timer to cancel, empty if there is only one' },
      all: { type: 'boolean', description: 'True to cancel every running timer' },
    } },
    summarize: () => 'Wyłączam timer',
    run: ({ label, all }) => cancelTimer({ label, all }),
  },
];
