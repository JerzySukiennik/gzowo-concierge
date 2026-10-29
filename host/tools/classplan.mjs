// Gzowo Concierge - tools that start the class plan job, carry Jurek's answers to it, show the finished PDF and send it to the class group.
import { startClassPlan, answerClassPlan, classPlanStatus, showClassPlan, sendClassPlan } from '../classplan.mjs';

const ROOM = 'pokoj';
const D = 'YYYY-MM-DD';

export const classPlanTools = [
  {
    name: 'class_plan_start',
    action: 'school.plan',
    policy: 'auto',
    description: "Start the weekly plan PDF for Jurek's class 8K: tests and quizzes with what each one covers, days off and school events, built by Claude Sonnet in the background from the school calendar, Pupka, the class WhatsApp groups and his school scans. It takes several minutes; you are told when it has a question for him or is done. Use when he asks for the class plan, 'plan klasy', 'ogłoszenie dla klasy na tydzień' or similar. Without dates it covers the next school week.",
    parameters: { type: 'object', properties: {
      from: { type: 'string', description: `Optional start, ${D}` },
      to: { type: 'string', description: `Optional end, ${D}` },
      note: { type: 'string', description: 'Optional things he already told you to include, in his words' },
    } },
    summarize: () => 'Zaczynam plan klasy',
    async run({ from, to, note }, ctx = {}) {
      const thread = ctx.thread || 'main';
      const s = startClassPlan({ from, to, note, origin: { kind: thread === ROOM ? 'room' : 'chat', thread } });
      return { started: true, period: s.period, note: 'Runs in the background for several minutes. Tell him briefly that you started it.' };
    },
  },
  {
    name: 'class_plan_answer',
    action: 'school.plan',
    policy: 'auto',
    description: 'Pass Jurek\'s answer to the open question from the class plan job, or extra information he gives for the plan while it is being made. Pass his words faithfully, do not shorten the facts.',
    parameters: { type: 'object', properties: { answer: { type: 'string', description: 'His answer or information, in Polish' } }, required: ['answer'] },
    summarize: () => 'Przekazuję odpowiedź do planu klasy',
    run: ({ answer }) => answerClassPlan(answer),
  },
  {
    name: 'class_plan_status',
    action: 'school.plan',
    policy: 'auto',
    description: 'State of the class plan job: running, waiting for his answer (with the question), done (with where the PDF is) or failed.',
    parameters: { type: 'object', properties: {} },
    summarize: () => 'Sprawdzam plan klasy',
    run: () => classPlanStatus(),
  },
  {
    name: 'class_plan_show',
    action: 'school.plan',
    policy: 'auto',
    description: 'Open the latest class plan PDF on the main Mac.',
    parameters: { type: 'object', properties: {} },
    summarize: () => 'Otwieram plan klasy na Macu',
    run: () => showClassPlan(),
  },
  {
    name: 'class_plan_send',
    action: 'whatsapp.send',
    policy: 'auto',
    description: "Send the finished class plan PDF to the class announcements WhatsApp group with the fixed short message and the note, both built in code. Use only when Jurek says to send or post the plan ('wyślij plan', 'wrzuć plan na grupę'). It goes out at once. If this plan was already sent it refuses; pass again=true only when he clearly asks to send it a second time.",
    parameters: { type: 'object', properties: { again: { type: 'boolean', description: 'Send a plan that was already sent once more' } } },
    summarize: () => 'Wysyłam plan klasy na grupę klasową',
    run: ({ again }) => sendClassPlan({ again: !!again }),
  },
];
