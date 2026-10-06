// Gzowo Concierge - CLI: run one message through the agent and print events.
import { run } from '../host/agent.mjs';

const thread = process.env.THREAD || 'cli';
const text = process.argv.slice(2).join(' ');
if (!text) { console.error('usage: npm run ask -- "message"'); process.exit(1); }
const t0 = Date.now();
await run(thread, text, e => {
  if (e.type === 'text') console.log(`\n${e.text}`);
  else if (e.type === 'tool') console.log(`  [${e.status}] ${e.summary}${e.error ? ' - ' + e.error : ''}`);
  else if (e.type === 'approval') console.log(`  [approval needed] ${e.summary} (${e.id})`);
  else console.log(e);
});
console.log(`\n(${((Date.now() - t0) / 1000).toFixed(1)}s)`);
