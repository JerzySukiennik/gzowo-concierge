// Gzowo Concierge - live web research through Gemini's Google Search grounding.
import { generate, textOf } from '../gemini.mjs';
import { config } from '../config.mjs';

const SEARCH_MODELS = (process.env.SEARCH_MODELS || 'gemini-2.5-flash,gemini-2.5-flash-lite,gemini-3.1-flash-lite,gemini-3.5-flash-lite').split(',');

export const webTools = [
  {
    name: 'web_search',
    action: 'web.search',
    policy: 'auto',
    description: 'Search the live web and get a researched answer with sources. Use for current facts, prices, opening hours, news, how-to questions.',
    parameters: { type: 'object', properties: { query: { type: 'string', description: 'What to find out, as a full question' } }, required: ['query'] },
    summarize: a => `Search the web: ${a.query}`,
    async run({ query }) {
      let res, lastErr;
      for (const model of SEARCH_MODELS) {
        try {
          res = await generate({
            model,
            system: 'You are a research tool. Answer precisely and briefly with concrete facts (numbers, names, dates, addresses). No filler.',
            contents: [{ role: 'user', parts: [{ text: query }] }],
            tools: [{ google_search: {} }],
            thinking: model.includes('2.5') ? null : 'minimal',
          });
          break;
        } catch (err) {
          lastErr = err;
          if (![429, 500, 503].includes(err.status)) throw err;
        }
      }
      if (!res) throw new Error(`Live search unavailable right now (${String(lastErr?.message).slice(0, 80)})`);
      const cand = res.candidates?.[0];
      const sources = (cand?.groundingMetadata?.groundingChunks || [])
        .map(c => c.web && { title: c.web.title, url: c.web.uri }).filter(Boolean).slice(0, 5);
      return { answer: textOf(cand?.content?.parts), sources };
    },
  },
];
