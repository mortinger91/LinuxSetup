// session-title — opencode plugin
//
// Adds a `session_title` tool that renames the calling session. Used by the `ticket-session-title`
// skill to put "Review: KDT-1234 <summary>" / "Implement: …" in the session name when working on or reviewing a ticket.
//
// opencode auto-generates a title after the first user message, asynchronously. If that lands
// after our rename it would clobber it, so a pinned title is re-applied once if it changes within
// PIN_WINDOW_MS. After that window, user renames win.

import { tool } from '@opencode-ai/plugin';

const PIN_WINDOW_MS = 60_000;
const MAX_TITLE = 100;

// Default export only: opencode loads every exported function as a separate plugin instance.
export default async ({ client }) => {
  // sessionID -> { title, until, directory }
  const pinned = new Map();

  const setTitle = (id, title, directory) =>
    client.session.update({
      path: { id },
      body: { title },
      query: directory ? { directory } : undefined,
      throwOnError: true,
    });

  return {
    tool: {
      session_title: tool({
        description:
          'Rename the current opencode session. Use for ticket sessions: ' +
          '"Review: KDT-1234 <summary>" or "Implement: KDT-1234 <summary>".',
        args: {
          title: tool.schema.string().min(1).describe('New session title'),
        },
        async execute({ title }, ctx) {
          const clean = title.replace(/\s+/g, ' ').trim().slice(0, MAX_TITLE);
          await setTitle(ctx.sessionID, clean, ctx.directory);
          pinned.set(ctx.sessionID, {
            title: clean,
            until: Date.now() + PIN_WINDOW_MS,
            directory: ctx.directory,
          });
          return `Session renamed to: ${clean}`;
        },
      }),
    },

    event: async ({ event }) => {
      if (event?.type !== 'session.updated') return;
      const info = event.properties?.info;
      const pin = info && pinned.get(info.id);
      if (!pin) return;
      if (Date.now() > pin.until) {
        pinned.delete(info.id);
        return;
      }
      if (info.title === pin.title) return;
      // Re-apply once only, so we never fight a deliberate rename.
      pinned.delete(info.id);
      try {
        await setTitle(info.id, pin.title, pin.directory);
      } catch {
        // Best effort; the tool call already reported success.
      }
    },
  };
};
