// Recipe import, generation, and label reading, behind the server
// (spec §5.3, §5.4, §5.5).
//
// One function for recipes because §5.4 asks for it: generation "runs through
// the same Edge Function → Claude API path as import". They differ only in what
// goes in — images or a URL for extraction, a conversation for generation —
// and both come back as the same recipe shape, so one adapter and one review
// screen serve both.
//
// Reading a nutrition label is a third mode here rather than a second function
// for a plainer reason: it is the same key, the same model, the same image
// plumbing and the same size caps, and splitting it would mean maintaining two
// of each. The name is now a slight misnomer — renaming a deployed function is
// a migration for a cosmetic gain, so it keeps it.
//
// The key is the reason this exists at all. ANTHROPIC_API_KEY in the client is
// a key anyone can pull out of the app bundle and spend (CLAUDE.md §8.1).
//
// verify_jwt is on (the default), so only a signed-in Hearth user can spend
// this project's quota.

const ANTHROPIC = 'https://api.anthropic.com/v1/messages';
const ANTHROPIC_VERSION = '2023-06-01';

/// Structured extraction rather than deep reasoning, and the cheaper tier by a
/// wide margin. One constant to change if the parse quality disappoints.
const MODEL = 'claude-sonnet-5';

/// Caps live here rather than only in the client. A client-side limit protects
/// nobody once the endpoint exists — anyone with a session can call it.
const MAX_IMAGES = 10;
const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
// Ten images rather than three, because a MacrosFirst recipe can run to that
// many screens. Sized against Anthropic's 32 MB request body rather than
// against ten times the per-image cap: base64 inflates by a third, so 18 MB of
// pictures arrives as about 24 MB of request, which leaves room. Ten
// downscaled screenshots come to a small fraction of it.
const MAX_TOTAL_BYTES = 18 * 1024 * 1024;
const MAX_MESSAGES = 40;
const MAX_URL_BYTES = 2 * 1024 * 1024;

/// The one shape both modes return, and the only thing the app parses.
///
/// Sections carry ingredients and directions as *text*, not as parsed rows:
/// Hearth already has parsers for both, they are already shown back to the user
/// before saving, and asking the model to also do the parsing would add a way
/// for it to be wrong that nothing downstream would catch.
const RECIPE_TOOL = {
  name: 'recipe',
  description: 'Return the recipe in Hearth\'s format.',
  input_schema: {
    type: 'object',
    properties: {
      title: { type: 'string' },
      servings: {
        type: 'number',
        description: 'Yield as a number of servings. Omit if not stated.',
      },
      prep_minutes: { type: 'number' },
      cook_minutes: { type: 'number' },
      cuisine: { type: 'string' },
      tags: { type: 'array', items: { type: 'string' } },
      sections: {
        type: 'array',
        description:
          'One section for a simple recipe. Use several only when the source ' +
          'itself groups them (a sauce, a marinade, a topping).',
        items: {
          type: 'object',
          properties: {
            name: {
              type: 'string',
              description: 'Empty for the main section.',
            },
            ingredients_text: {
              type: 'string',
              description:
                'One ingredient per line, as written. Every ingredient a ' +
                "step in THIS section uses belongs here, even if the source " +
                'printed it under another heading.',
            },
            directions_text: {
              type: 'string',
              description:
                'One step per line, without step numbers, in the order they ' +
                'are performed. A step belongs to the section whose ' +
                'ingredients it uses.',
            },
          },
          required: ['ingredients_text', 'directions_text'],
        },
      },
      uncertain: {
        type: 'array',
        description:
          'Anything you could not read confidently — an ambiguous quantity, ' +
          'a cut-off line, a guessed yield. Name the field and say what to ' +
          'check. Empty when the source was clear.',
        items: {
          type: 'object',
          properties: {
            field: { type: 'string' },
            note: { type: 'string' },
          },
          required: ['field', 'note'],
        },
      },
      reply: {
        type: 'string',
        description:
          'Generation only: what to say back in the chat, one or two ' +
          'sentences. Omit when extracting.',
      },
      estimates: {
        type: 'array',
        description:
          'Generation only, and a LAST RESORT. For each ingredient line, ' +
          'your rough estimate of what that line contributes AS WRITTEN. ' +
          'The app looks every ingredient up in real nutrition databases and ' +
          'uses these only for the ones it cannot find, labelled as ' +
          'estimates. Omit entirely when extracting.',
        items: {
          type: 'object',
          properties: {
            ingredient: {
              type: 'string',
              description: 'The ingredient line, exactly as you wrote it.',
            },
            kcal: { type: 'number' },
            protein_g: { type: 'number' },
            carb_g: { type: 'number' },
            fat_g: { type: 'number' },
          },
          required: ['ingredient', 'kcal'],
        },
      },
    },
    required: ['title', 'sections'],
  },
} as const;

const EXTRACT_PROMPT = `You extract recipes from images and web pages into a
structured format.

Transcribe what is actually there. Do not improve the recipe, round quantities,
convert units, or add steps the source does not contain — the user is migrating
their own library and expects to recognise it.

Several images are pages or screens of ONE recipe. Stitch them into a single
recipe rather than returning the first.

Keep each ingredient line as written, including the quantity and any prep note
("3 cloves garlic, minced"). Keep directions as prose, one step per line, with
no numbering.

Sections have to hold together, because the app shows each step beside the
amounts from its own section:

- put a step in the section whose ingredients it uses, and put those
  ingredients in that same section. A step that whisks cornstarch belongs with
  the cornstarch, wherever the source happened to print it;
- order the steps within a section the way they are performed, and order the
  sections the way they are worked through. Marinating the beef comes before
  serving it, whatever order the page listed things in;
- only split into sections where the source really has separate components,
  and never leave a section holding steps from a different part of the recipe.

A line that explains rather than instructs — "this keeps lean beef from going
grainy", "the sauce will thicken as it cools" — is not a step. Attach it to
the end of the step it explains, in the same line, or leave it out. A numbered
instruction the cook cannot do is one more thing to read and nothing to do.

If something is genuinely unreadable or ambiguous — a quantity that could be
1/2 or 12, a line cut off at the edge — transcribe your best reading AND list
it in uncertain. A flagged guess is useful; a confident wrong number is not.`;

const GENERATE_PROMPT = `You write recipes for a household meal-planning app.

Produce a complete, genuinely cookable recipe: real quantities, real times, and
steps someone can follow without prior knowledge of the dish.

Respect the user's food profile absolutely. An allergy is a hard constraint, not
a preference. Dislikes should be avoided unless the user overrides them in the
conversation.

Always fill in reply — it is the only thing the user reads in the chat, and a
recipe that arrives without a word about it looks like a machine answered.

When the user asks for a change, return the whole revised recipe rather than a
diff, and say in reply what you actually changed. That sentence is the whole
value of a refinement: without it they have to diff two recipes by eye.

Do not put calories or macros in the recipe text. The app computes those from
real nutrition databases, and a number written into a step would be believed
without ever being checked.

Do fill in estimates: one entry per ingredient line, for what that line
contributes as written. These are a fallback the app uses only for ingredients
it cannot find in a real database, and it labels them as estimates when it
does. A rough number that is honest about being rough beats a silent zero.`;

/// One serving of one food, as a Nutrition Facts panel states it.
///
/// The unit is an enum rather than free text so the model cannot answer in
/// something the app then silently drops — "serving", "portion", "scoop" all
/// arrive as words Hearth has no conversion for, and a serving that vanishes
/// between the photo and the review screen is worse than one that was never
/// offered.
const LABEL_TOOL = {
  name: 'nutrition_label',
  description: "Return what the food's label states.",
  input_schema: {
    type: 'object',
    properties: {
      name: {
        type: 'string',
        description:
          'What the food is, as the packet names it — "Shredded Sharp ' +
          'Cheddar Cheese". Omit if the panel is photographed alone.',
      },
      brand: { type: 'string', description: 'Omit if not visible.' },
      servings: {
        type: 'array',
        description:
          'One entry per way the label expresses the SAME serving. A line ' +
          'reading "Serving size 1oz (28g/about 1/4 cup)" is three ways of ' +
          'saying one portion: return the ounces and the cups as two ' +
          'entries with identical macros. Do not return the grams as well ' +
          'when an ounce figure is given for the same portion.',
        items: {
          type: 'object',
          properties: {
            amount: { type: 'number', description: 'How much. 0.25 for 1/4.' },
            unit: {
              type: 'string',
              enum: ['g', 'ml', 'oz', 'lb', 'cup', 'tbsp', 'tsp', 'item'],
            },
            kcal: { type: 'number' },
            protein_g: { type: 'number' },
            carb_g: { type: 'number' },
            fat_g: { type: 'number' },
          },
          required: ['amount', 'unit', 'kcal'],
        },
      },
      uncertain: {
        type: 'array',
        description: 'Anything blurred, cut off, or ambiguous.',
        items: {
          type: 'object',
          properties: {
            field: { type: 'string' },
            note: { type: 'string' },
          },
          required: ['field', 'note'],
        },
      },
    },
    required: ['servings'],
  },
} as const;

const LABEL_PROMPT = `You read Nutrition Facts panels off packaging.

Transcribe the printed numbers. Never compute: do not scale a per-100 g column
to a serving, do not infer fat from calories, do not convert between units the
label does not itself give. A number the user can find on their own packet is
checkable; one you worked out is not.

The serving line is the important part, and US labels usually state one portion
several ways: "Serving size 1oz (28g/about 1/4 cup)". Return each measurable
way as its own serving with the SAME macros — the weight and the volume of one
portion together are the only statement of how dense the food is, and it is
what lets the app use this food in a recipe that measures in cups. Prefer the
ounce figure over the gram figure when both are given for the same portion; if
only grams are printed, return the grams.

Ignore "servings per container" — that is how many are in the packet, not a
portion anybody eats.

Return at most the servings the label states. Do not invent a 100 g row.

If a digit is blurred, a line is cut off, or a figure could be read two ways,
transcribe your best reading AND list it in uncertain. A flagged guess is
useful; a confident wrong number is not.`;

interface Uncertain {
  field: string;
  note: string;
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method !== 'POST') {
    return json({ error: 'POST only' }, 405);
  }

  const key = Deno.env.get('ANTHROPIC_API_KEY');
  if (!key) {
    // Configuration, not a failed import — say so plainly rather than
    // returning an empty recipe the client would read as "nothing found".
    return json({ error: 'ANTHROPIC_API_KEY is not set on this project' }, 500);
  }

  let body: {
    mode?: string;
    images?: string[];
    url?: string;
    messages?: { role?: string; text?: string }[];
    profile?: Record<string, unknown>;
  };
  try {
    body = await request.json();
  } catch {
    return json({ error: 'expected a JSON body' }, 400);
  }

  const mode = (body.mode ?? '').trim();
  if (mode !== 'extract' && mode !== 'generate' && mode !== 'label') {
    return json({ error: 'mode must be extract, generate or label' }, 400);
  }

  try {
    if (mode === 'label') {
      const input = await ask(
        LABEL_PROMPT,
        labelContent(body.images ?? []),
        key,
        LABEL_TOOL,
      );
      return json(shapeLabel(input));
    }

    const content = mode === 'extract'
      ? await extractContent(body.images ?? [], (body.url ?? '').trim())
      : generateContent(body.messages ?? [], body.profile ?? {});

    const system = mode === 'extract' ? EXTRACT_PROMPT : GENERATE_PROMPT;
    return json(shape(await ask(system, content, key, RECIPE_TOOL)));
  } catch (error) {
    // `${error}` on an Error stringifies as "Error: bad request: …", so the
    // prefix check never matched: every malformed request came back 502 with
    // "Error: bad request:" showing through to the user. A 502 is retryable
    // and "you sent no photo" is not, so the app offered a retry that could
    // only fail the same way.
    const message = error instanceof Error ? error.message : `${error}`;
    // A bad request from the client is a 400 it can act on; anything else is
    // upstream, and the app offers a retry rather than losing the input.
    const status = message.startsWith('bad request:') ? 400 : 502;
    return json({ error: message.replace(/^bad request: /, '') }, status);
  }
});

/// Images and/or a page, as Claude content blocks.
async function extractContent(
  images: string[],
  url: string,
): Promise<unknown[]> {
  if (images.length === 0 && !url) {
    throw new Error('bad request: give images or a url');
  }

  const content: unknown[] = imageBlocks(images);

  if (url) {
    content.push({ type: 'text', text: await fetchPage(url) });
  }

  content.push({
    type: 'text',
    text: images.length > 1
      ? 'These images are one recipe. Extract it.'
      : 'Extract the recipe.',
  });

  return content;
}

/// A label, as Claude content blocks.
///
/// Several images are the same packet from more than one angle — a panel is
/// often easier to read in two shots than one — so they are stitched into a
/// single reading rather than treated as several foods.
function labelContent(images: string[]): unknown[] {
  if (images.length === 0) {
    throw new Error('bad request: give a photo of the label');
  }

  return [
    ...imageBlocks(images),
    {
      type: 'text',
      text: images.length > 1
        ? 'These are photos of one packet. Read its label.'
        : 'Read this label.',
    },
  ];
}

/// Images as content blocks, size-capped.
///
/// The caps live here rather than only in the client because a client-side
/// limit protects nobody once the endpoint exists — anyone with a session can
/// call it (CLAUDE.md §8.1).
function imageBlocks(images: string[]): unknown[] {
  if (images.length > MAX_IMAGES) {
    throw new Error(`bad request: at most ${MAX_IMAGES} images`);
  }

  const blocks: unknown[] = [];
  let total = 0;

  for (const raw of images) {
    const data = stripDataUrl(raw);
    // base64 is 4 characters per 3 bytes; close enough to hold a line on size
    // without decoding the whole thing to measure it.
    const bytes = Math.floor((data.length * 3) / 4);
    total += bytes;
    if (bytes > MAX_IMAGE_BYTES) {
      throw new Error('bad request: an image is too large');
    }
    if (total > MAX_TOTAL_BYTES) {
      throw new Error('bad request: those images are too large together');
    }

    blocks.push({
      type: 'image',
      source: { type: 'base64', media_type: mediaTypeOf(raw), data },
    });
  }

  return blocks;
}

/// The conversation so far, plus the profile as standing context.
function generateContent(
  messages: { role?: string; text?: string }[],
  profile: Record<string, unknown>,
): unknown[] {
  const turns = messages
    .filter((m) => (m.text ?? '').trim().length > 0)
    .slice(-MAX_MESSAGES);

  if (turns.length === 0) {
    throw new Error('bad request: nothing to generate from');
  }

  const content: unknown[] = [];
  if (Object.keys(profile).length > 0) {
    content.push({
      type: 'text',
      text: `The user's food profile:\n${JSON.stringify(profile, null, 2)}`,
    });
  }

  // Flattened into one turn rather than a multi-turn exchange: the tool is
  // forced on every call, so the assistant's side of the conversation is a
  // tool result rather than prose, and replaying that adds nothing the reply
  // text does not already carry.
  content.push({
    type: 'text',
    text: turns
      .map((m) => `${m.role === 'assistant' ? 'You' : 'User'}: ${m.text}`)
      .join('\n\n'),
  });

  return content;
}

/// Fetches a recipe page as text.
///
/// Deliberately crude: tags are stripped and the model reads the remains. A
/// real HTML parse or a JSON-LD reader would be better and is a redeploy away,
/// but recipe sites disagree about their own markup often enough that the
/// model reading the visible words is the more reliable floor.
async function fetchPage(url: string): Promise<string> {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    throw new Error('bad request: that is not a url');
  }
  if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') {
    throw new Error('bad request: only http and https urls');
  }

  const response = await fetch(parsed, {
    headers: { 'user-agent': 'Hearth/1.0 (household recipe app)' },
    redirect: 'follow',
    signal: AbortSignal.timeout(10_000),
  });
  if (!response.ok) {
    throw new Error(`that page returned ${response.status}`);
  }

  const html = (await response.text()).slice(0, MAX_URL_BYTES);
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/gi, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 60_000);
}

/// Asks Claude, forcing the tool so the answer is a validated object.
///
/// Forcing it matters: a model asked for JSON in prose will occasionally wrap
/// it in an apology, and that becomes a parse error in Dart. Forced tool use
/// makes a malformed answer the API's problem, not the app's.
async function ask(
  system: string,
  content: unknown[],
  key: string,
  tool: { name: string },
): Promise<Record<string, unknown>> {
  const response = await fetch(ANTHROPIC, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-api-key': key,
      'anthropic-version': ANTHROPIC_VERSION,
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 4096,
      system,
      tools: [tool],
      tool_choice: { type: 'tool', name: tool.name },
      messages: [{ role: 'user', content }],
    }),
    signal: AbortSignal.timeout(90_000),
  });

  if (!response.ok) {
    const detail = await response.text();
    throw new Error(`Claude returned ${response.status}: ${detail.slice(0, 300)}`);
  }

  const payload = await response.json();
  const block = (payload?.content ?? []).find(
    (c: { type?: string }) => c?.type === 'tool_use',
  );
  if (!block?.input) {
    throw new Error('Claude returned nothing readable');
  }

  return block.input;
}

/// Narrows what the model returned to the shape the app is promised.
///
/// Done here rather than in Dart so a change in what comes back is a redeploy
/// rather than an App Store release — the same reason the USDA function parses
/// server-side.
function shape(input: Record<string, unknown>): Record<string, unknown> {
  const sections = Array.isArray(input.sections) ? input.sections : [];

  return {
    recipe: {
      title: text(input.title),
      servings: number(input.servings),
      prep_minutes: number(input.prep_minutes),
      cook_minutes: number(input.cook_minutes),
      cuisine: text(input.cuisine) || null,
      tags: Array.isArray(input.tags)
        ? input.tags.map(text).filter((t) => t.length > 0)
        : [],
      sections: sections.map((s: Record<string, unknown>) => ({
        name: text(s?.name),
        ingredients_text: text(s?.ingredients_text),
        directions_text: text(s?.directions_text),
      })),
    },
    estimates: Array.isArray(input.estimates)
      ? (input.estimates as Record<string, unknown>[])
        .filter((e) => text(e?.ingredient).length > 0)
        .map((e) => ({
          ingredient: text(e.ingredient),
          kcal: number(e.kcal) ?? 0,
          protein_g: number(e.protein_g) ?? 0,
          carb_g: number(e.carb_g) ?? 0,
          fat_g: number(e.fat_g) ?? 0,
        }))
      : [],
    uncertain: Array.isArray(input.uncertain)
      ? (input.uncertain as Uncertain[])
        .filter((u) => u?.field || u?.note)
        .map((u) => ({ field: text(u.field), note: text(u.note) }))
      : [],
    reply: text(input.reply) || null,
  };
}

/// Narrows a label reading the same way, and drops what the app cannot use.
///
/// A serving with a unit Hearth does not know is dropped rather than defaulted
/// to grams: a portion silently reinterpreted as a weight it is not would put
/// a wrong number into a day, which is the one failure mode a review screen
/// cannot catch, because it looks correct.
function shapeLabel(input: Record<string, unknown>): Record<string, unknown> {
  const units = ['g', 'ml', 'oz', 'lb', 'cup', 'tbsp', 'tsp', 'item'];
  const servings = Array.isArray(input.servings) ? input.servings : [];

  return {
    name: text(input.name) || null,
    brand: text(input.brand) || null,
    servings: (servings as Record<string, unknown>[])
      .filter((s) => {
        const amount = number(s?.amount);
        return amount !== null && amount > 0 && units.includes(text(s?.unit));
      })
      .map((s) => ({
        amount: number(s.amount),
        unit: text(s.unit),
        kcal: number(s.kcal) ?? 0,
        protein_g: number(s.protein_g) ?? 0,
        carb_g: number(s.carb_g) ?? 0,
        fat_g: number(s.fat_g) ?? 0,
      })),
    uncertain: Array.isArray(input.uncertain)
      ? (input.uncertain as Uncertain[])
        .filter((u) => u?.field || u?.note)
        .map((u) => ({ field: text(u.field), note: text(u.note) }))
      : [],
  };
}

function text(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

function number(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

function stripDataUrl(value: string): string {
  const comma = value.indexOf(',');
  return value.startsWith('data:') && comma >= 0
    ? value.slice(comma + 1)
    : value;
}

/// Claude accepts jpeg, png, gif and webp. Anything else is called jpeg and
/// left to fail loudly upstream rather than silently here.
function mediaTypeOf(value: string): string {
  const match = /^data:(image\/[a-z+]+);/i.exec(value);
  const declared = match?.[1]?.toLowerCase();
  const allowed = ['image/jpeg', 'image/png', 'image/gif', 'image/webp'];
  return declared && allowed.includes(declared) ? declared : 'image/jpeg';
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}
