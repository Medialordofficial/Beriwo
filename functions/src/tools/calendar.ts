import { z } from "zod";
import { defineProtectedTool } from "../auth0.js";

let _cached: ReturnType<typeof register> | null = null;
export function getCalendarTools() {
  if (!_cached) _cached = register();
  return _cached;
}

function register() {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const { getAccessTokenFromTokenVault } = require("@auth0/ai-genkit");

  const listUpcomingEvents = defineProtectedTool(
  {
    name: "list_upcoming_events",
    description:
      "List upcoming events from the user's Google Calendar",
    inputSchema: z.object({
      maxResults: z
        .number()
        .int()
        .min(1)
        .max(20)
        .default(10)
        .describe("Number of events to retrieve"),
      timeMin: z
        .string()
        .optional()
        .describe("Start of time range (ISO 8601). Defaults to now."),
      timeMax: z
        .string()
        .optional()
        .describe("End of time range (ISO 8601)."),
    }),
    outputSchema: z.object({
      events: z.array(
        z.object({
          id: z.string(),
          summary: z.string(),
          start: z.string(),
          end: z.string(),
          location: z.string().optional(),
          description: z.string().optional(),
        })
      ),
    }),
  },
  async ({ maxResults, timeMin, timeMax }) => {
      const accessToken = getAccessTokenFromTokenVault();

      const params = new URLSearchParams({
        maxResults: String(maxResults),
        singleEvents: "true",
        orderBy: "startTime",
        timeMin: timeMin || new Date().toISOString(),
      });
      if (timeMax) params.set("timeMax", timeMax);

      const res = await fetch(
        `https://www.googleapis.com/calendar/v3/calendars/primary/events?${params}`,
        { headers: { Authorization: `Bearer ${accessToken}` } }
      );

      if (!res.ok) {
        throw new Error(`Calendar API error: ${res.status}`);
      }

      const data = (await res.json()) as {
        items?: {
          id: string;
          summary?: string;
          start?: { dateTime?: string; date?: string };
          end?: { dateTime?: string; date?: string };
          location?: string;
          description?: string;
        }[];
      };

      const events = (data.items || []).map((e) => ({
        id: e.id,
        summary: e.summary || "(No title)",
        start: e.start?.dateTime || e.start?.date || "",
        end: e.end?.dateTime || e.end?.date || "",
        location: e.location,
        description: e.description?.slice(0, 500),
      }));

      return { events };
  }
);

const createEvent = defineProtectedTool(
  {
    name: "create_calendar_event",
    description: "Create a new event on the user's Google Calendar",
    inputSchema: z.object({
      summary: z.string().describe("Event title"),
      startDateTime: z
        .string()
        .describe("Start date/time in ISO 8601 format"),
      endDateTime: z.string().describe("End date/time in ISO 8601 format"),
      description: z.string().optional().describe("Event description"),
      location: z.string().optional().describe("Event location"),
    }),
    outputSchema: z.object({
      id: z.string(),
      summary: z.string(),
      htmlLink: z.string(),
    }),
  },
  async ({ summary, startDateTime, endDateTime, description, location }) => {
      const accessToken = getAccessTokenFromTokenVault();

      const res = await fetch(
        "https://www.googleapis.com/calendar/v3/calendars/primary/events",
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            summary,
            start: { dateTime: startDateTime },
            end: { dateTime: endDateTime },
            description,
            location,
          }),
        }
      );

      if (!res.ok) {
        throw new Error(`Calendar API error: ${res.status}`);
      }

      const event = (await res.json()) as {
        id: string;
        summary: string;
        htmlLink: string;
      };
      return {
        id: event.id,
        summary: event.summary,
        htmlLink: event.htmlLink,
      };
  }
);

return { listUpcomingEvents, createEvent };
}
