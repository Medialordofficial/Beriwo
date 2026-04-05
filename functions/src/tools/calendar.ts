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
        .max(50)
        .default(10)
        .describe("Number of events to retrieve (max 50)"),
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

      // Gemini sometimes sends objects instead of ISO strings — normalize
      const safeTimeMin =
        typeof timeMin === "string" && timeMin.length > 0
          ? timeMin
          : new Date().toISOString();
      const safeTimeMax =
        typeof timeMax === "string" && timeMax.length > 0 ? timeMax : undefined;

      const params = new URLSearchParams({
        maxResults: String(Math.min(Math.max(maxResults || 10, 1), 20)),
        singleEvents: "true",
        orderBy: "startTime",
        timeMin: safeTimeMin,
      });
      if (safeTimeMax) params.set("timeMax", safeTimeMax);

      const res = await fetch(
        `https://www.googleapis.com/calendar/v3/calendars/primary/events?${params}`,
        { headers: { Authorization: `Bearer ${accessToken}` } }
      );

      if (!res.ok) {
        const errBody = await res.text().catch(() => "");
        require("firebase-functions/v2").logger.warn(`Calendar API error: ${res.status} ${errBody.substring(0, 300)}`);
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

const updateEvent = defineProtectedTool(
  {
    name: "update_calendar_event",
    description: "Update an existing event on the user's Google Calendar (e.g. reschedule, rename, change location)",
    inputSchema: z.object({
      eventId: z.string().describe("The Google Calendar event ID"),
      summary: z.string().optional().describe("New event title"),
      startDateTime: z.string().optional().describe("New start date/time (ISO 8601)"),
      endDateTime: z.string().optional().describe("New end date/time (ISO 8601)"),
      description: z.string().optional().describe("New event description"),
      location: z.string().optional().describe("New event location"),
    }),
    outputSchema: z.object({
      id: z.string(),
      summary: z.string(),
      htmlLink: z.string(),
    }),
  },
  async ({ eventId, summary, startDateTime, endDateTime, description, location }) => {
    const accessToken = getAccessTokenFromTokenVault();

    const body: Record<string, any> = {};
    if (summary) body.summary = summary;
    if (startDateTime) body.start = { dateTime: startDateTime };
    if (endDateTime) body.end = { dateTime: endDateTime };
    if (description !== undefined) body.description = description;
    if (location !== undefined) body.location = location;

    const res = await fetch(
      `https://www.googleapis.com/calendar/v3/calendars/primary/events/${eventId}`,
      {
        method: "PATCH",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
      }
    );

    if (!res.ok) throw new Error(`Calendar API error: ${res.status}`);

    const event = (await res.json()) as { id: string; summary: string; htmlLink: string };
    return { id: event.id, summary: event.summary, htmlLink: event.htmlLink };
  }
);

const deleteEvent = defineProtectedTool(
  {
    name: "delete_calendar_event",
    description: "Delete/cancel an event from the user's Google Calendar",
    inputSchema: z.object({
      eventId: z.string().describe("The Google Calendar event ID to delete"),
    }),
    outputSchema: z.object({
      status: z.string(),
    }),
  },
  async ({ eventId }) => {
    const accessToken = getAccessTokenFromTokenVault();

    const res = await fetch(
      `https://www.googleapis.com/calendar/v3/calendars/primary/events/${eventId}`,
      {
        method: "DELETE",
        headers: { Authorization: `Bearer ${accessToken}` },
      }
    );

    if (!res.ok) throw new Error(`Calendar API error: ${res.status}`);
    return { status: "deleted" };
  }
);

return { listUpcomingEvents, createEvent, updateEvent, deleteEvent };
}
