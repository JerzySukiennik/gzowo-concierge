// Gzowo Concierge - shared registry of active live voice sessions (breaks an import cycle).
export const live = { sessions: new Set() };
